import Foundation
import ImageIO
import UniformTypeIdentifiers

/// "WebP": images to WebP through the embedded ffmpeg (§3), see WebPEncoder.
struct ImageToWebPOperation: FileOperation {
    let id = "convert.webp"
    let kind = WheelMode.convert
    let title = "WebP"
    let symbol = "photo"

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
            outputs.append(try await context.output.commitAsync(baseName: input.baseName, fileExtension: "webp",
                                                                for: input) { temporary in
                try await WebPEncoder.encode(image, quality: context.quality.webPQuality, to: temporary, with: ffmpeg)
            })
            progress(Double(index + 1) / Double(inputs.count))
        }
        return outputs
    }
}
