import Foundation
import ImageIO
import Quartz
import UniformTypeIdentifiers

/// "Compresser" (§5.4): images re-encoded at 75 % (PNG and TIFF without
/// loss), PDFs through the system "Reduce File Size" filter, videos
/// re-encoded in HEVC at most 1080p. The format is kept, and a result that
/// is not smaller is refused instead of being handed over.
struct CompressOperation: FileOperation {
    static let suffix = " (compressé)"
    static let imageQuality = 0.75
    static let videoMaxLongSide = 1920
    /// TIFF compression tag value for LZW (lossless).
    private static let tiffLZW = 5

    let id = "tool.compress"
    let kind = WheelMode.tools
    let title = "Compresser"
    let symbol = "arrow.down.right.and.arrow.up.left"
    var usesMediaEngine: Bool { true }

    /// BMP is left out: re-encoding it gains nothing.
    static func isCompressibleImage(_ type: UTType) -> Bool {
        type.conforms(to: .webP) || ImageFormat.matching(type).map { $0 != .bmp } ?? false
    }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy {
            Self.isCompressibleImage($0) || FileTypes.isPDF($0) || FileTypes.isVideo($0)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { progress((Double(index) + $0) / Double(inputs.count)) }
            let type = FileTypes.type(of: input)
            let baseName = input.baseName + Self.suffix
            if FileTypes.isVideo(type) {
                outputs.append(try await compressVideo(input, baseName: baseName, context: context, progress: share))
            } else {
                outputs.append(try await context.output.commitAsync(baseName: baseName,
                                                                    fileExtension: input.pathExtension.lowercased(),
                                                                    for: input) { temporary in
                    if FileTypes.isPDF(type) {
                        try Self.compressPDF(input, to: temporary)
                    } else {
                        try await Self.compressImage(input, type: type, to: temporary, context: context)
                    }
                    try Self.requireSmaller(temporary, than: input)
                })
            }
            share(1)
        }
        return outputs
    }

    private static func compressImage(_ input: URL, type: UTType, to url: URL, context: OperationContext) async throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = ImageConverter.uprightImage(from: source) else {
            throw OperationError.unreadableImage
        }
        var properties = ImageConverter.metadata(of: source, stripsLocation: context.stripsLocation)
        if type.conforms(to: .tiff) {
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = tiffLZW
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        try await ImageRewriter.write(image, like: type, to: url, quality: imageQuality, properties: properties,
                                      ffmpeg: context.ffmpeg)
    }

    /// The system filter behind Preview's "Reduce File Size": images are
    /// downsampled and JPEG-compressed, text and vectors are kept. (PDFKit's
    /// saveImagesAsJPEG / optimizeImagesForScreen write options were measured
    /// to have no effect.) Links and annotations are not carried over.
    private static let reduceFileSizeFilter = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")

    private static func compressPDF(_ input: URL, to url: URL) throws {
        // Reports locked or unreadable PDFs with a human message.
        _ = try PDFConverter.openDocument(input)
        guard let document = CGPDFDocument(input as CFURL),
              let filter = QuartzFilter(url: reduceFileSizeFilter),
              let context = CGContext(url as CFURL, mediaBox: nil, nil),
              filter.apply(to: context) else {
            throw OperationError.writeFailed
        }
        defer { context.closePDF() }
        for index in 1...document.numberOfPages {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw OperationError.unreadablePDF }
            // Redraw upright: the page's /Rotate is applied by the drawing transform.
            let crop = page.getBoxRect(.cropBox)
            let quarterTurn = (page.rotationAngle / 90) % 2 != 0
            var box = CGRect(x: 0, y: 0, width: quarterTurn ? crop.height : crop.width,
                             height: quarterTurn ? crop.width : crop.height)
            context.beginPage(mediaBox: &box)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: box, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.endPage()
        }
    }

    /// HEVC bitrate for the output's longer side: sensible for 1080p and below.
    static func videoBitrate(for probe: MediaProbe) -> String {
        let longSide = min(max(probe.width ?? videoMaxLongSide, probe.height ?? 0), videoMaxLongSide)
        switch longSide {
        case 1600...: return "4M"
        case 1000...: return "2500k"
        default: return "1500k"
        }
    }

    private func compressVideo(_ input: URL, baseName: String, context: OperationContext,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        let probe: MediaProbe
        do {
            probe = try await ffmpeg.probe(input)
        } catch let error as FFmpegError {
            throw OperationError.unreadableVideo.withDetail(error.description)
        }
        guard probe.videoCodec != nil else { throw OperationError.noVideo }
        let isMOV = FileTypes.type(of: input).conforms(to: .quickTimeMovie)

        return try await context.output.commitAsync(baseName: baseName, fileExtension: isMOV ? "mov" : "mp4",
                                                    for: input) { temporary in
            var arguments = ["-i", input.path, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn",
                             "-vf", VideoScaling.fitting(longSide: Self.videoMaxLongSide),
                             "-c:v", "hevc_videotoolbox", "-b:v", Self.videoBitrate(for: probe),
                             "-tag:v", "hvc1", "-c:a", "aac_at", "-b:a", "128k"]
            if !isMOV { arguments += ["-movflags", "+faststart"] }
            do {
                try await ffmpeg.convert(arguments + [temporary.path], duration: probe.duration, progress: progress)
            } catch let error as FFmpegError {
                throw OperationError.unreadableVideo.withDetail(error.description)
            }
            try Self.requireSmaller(temporary, than: input)
        }
    }

    private static func requireSmaller(_ output: URL, than input: URL) throws {
        func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        guard size(output) < size(input) else { throw OperationError.alreadyCompressed }
    }
}
