import Foundation
import ImageIO
import UniformTypeIdentifiers

/// "WebP": ImageIO cannot encode WebP, so the upright image goes through a
/// temporary PNG and the embedded ffmpeg's libwebp (§3). Metadata is not kept.
struct ImageToWebPOperation: FileOperation {
    static let quality = "90"

    let id = "convert.webp"
    let kind = WheelMode.convert
    let title = "WebP"
    let symbol = "globe"

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { FileTypes.isImage($0) && !$0.conforms(to: .webP) }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                  let image = ImageConverter.uprightImage(from: source) else {
                throw OperationError.unreadableImage
            }
            let png = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: png) }
            try ImageConverter.write(image, as: .png, to: png)

            outputs.append(try await context.output.commitAsync(baseName: input.baseName, fileExtension: "webp",
                                                                for: input) { temporary in
                do {
                    try await ffmpeg.convert(["-i", png.path, "-c:v", "libwebp", "-quality", Self.quality, temporary.path],
                                             duration: nil) { _ in }
                } catch let error as FFmpegError {
                    throw OperationError.writeFailed.withDetail(error.description)
                }
            })
            progress(Double(index + 1) / Double(inputs.count))
        }
        return outputs
    }
}
