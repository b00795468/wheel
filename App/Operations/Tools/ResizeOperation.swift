import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Presets of "Redimensionner" (§5.4): half size, or a longer side of
/// 1920, 1280 or 800 px. The aspect ratio is kept and nothing is enlarged.
enum ResizePreset: CaseIterable, Sendable {
    case half, long1920, long1280, long800

    var maxLongSide: Int? {
        switch self {
        case .half: nil
        case .long1920: 1920
        case .long1280: 1280
        case .long800: 800
        }
    }

    var id: String { maxLongSide.map { String($0) } ?? "50" }
    var title: String { maxLongSide.map { "\($0) px" } ?? "50 %" }

    /// Longer side of the result, nil when the file is already small enough.
    func targetLongSide(width: Int, height: Int) -> Int? {
        let longSide = max(width, height)
        guard let limit = maxLongSide else { return longSide > 1 ? longSide / 2 : nil }
        return longSide > limit ? limit : nil
    }

    var videoFilter: String {
        maxLongSide.map { VideoScaling.fitting(longSide: $0) } ?? VideoScaling.half
    }
}

/// One preset of "Redimensionner", for images (format kept) and videos
/// (H.264). The four presets share a sub-wheel.
struct ResizeOperation: FileOperation {
    static let group = OperationGroup(id: "tool.resize", title: "Redimensionner", symbol: "aspectratio")

    let preset: ResizePreset

    var id: String { "tool.resize.\(preset.id)" }
    var kind: WheelMode { .tools }
    var title: String { preset.title }
    var symbol: String { "aspectratio" }
    var group: OperationGroup? { Self.group }
    var usesMediaEngine: Bool { true }
    var progressTitle: String { "Redimensionnement à \(preset.title)" }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy {
            (FileTypes.isImage($0) && ImageRewriter.canRewrite($0)) || FileTypes.isVideo($0)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { progress((Double(index) + $0) / Double(inputs.count)) }
            let type = FileTypes.type(of: input)
            let baseName = "\(input.baseName) (\(preset.title))"
            if FileTypes.isVideo(type) {
                outputs.append(try await resizeVideo(input, baseName: baseName, context: context, progress: share))
            } else {
                outputs.append(try await context.output.commitAsync(baseName: baseName,
                                                                    fileExtension: input.pathExtension.lowercased(),
                                                                    for: input) { temporary in
                    try await resizeImage(input, type: type, to: temporary, context: context)
                })
            }
            share(1)
        }
        return outputs
    }

    private func resizeImage(_ input: URL, type: UTType, to url: URL, context: OperationContext) async throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw OperationError.unreadableImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { throw OperationError.unreadableImage }
        guard let longSide = preset.targetLongSide(width: width, height: height) else {
            throw OperationError.alreadySmall(than: preset.title)
        }
        guard let image = ImageConverter.downscaledImage(from: source, maxPixelSize: longSide) else {
            throw OperationError.unreadableImage
        }
        try await ImageRewriter.write(image, like: type, to: url, quality: context.quality.imageQuality,
                                      properties: ImageConverter.metadata(of: source, stripsLocation: context.stripsLocation),
                                      ffmpeg: context.ffmpeg)
    }

    private func resizeVideo(_ input: URL, baseName: String, context: OperationContext,
                             progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        let probe: MediaProbe
        do {
            probe = try await ffmpeg.probe(input)
        } catch let error as FFmpegError {
            throw OperationError.unreadableVideo.withDetail(error.description)
        }
        guard probe.videoCodec != nil else { throw OperationError.noVideo }
        if let width = probe.width, let height = probe.height,
           preset.targetLongSide(width: width, height: height) == nil {
            throw OperationError.alreadySmall(than: preset.title)
        }
        let isMOV = FileTypes.type(of: input).conforms(to: .quickTimeMovie)

        return try await context.output.commitAsync(baseName: baseName, fileExtension: isMOV ? "mov" : "mp4",
                                                    for: input) { temporary in
            var arguments = ["-i", input.path, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn",
                             "-vf", preset.videoFilter,
                             "-c:v", "h264_videotoolbox", "-q:v", context.quality.videoQuality, "-pix_fmt", "yuv420p",
                             "-tag:v", "avc1"]
            arguments += probe.audioCodec == "aac" ? ["-c:a", "copy"] : ["-c:a", "aac_at", "-b:a", "192k"]
            if !isMOV { arguments += ["-movflags", "+faststart"] }
            do {
                try await ffmpeg.convert(arguments + [temporary.path], duration: probe.duration, progress: progress)
            } catch let error as FFmpegError {
                throw OperationError.unreadableVideo.withDetail(error.description)
            }
        }
    }
}
