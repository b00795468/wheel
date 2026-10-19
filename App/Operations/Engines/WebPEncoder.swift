import CoreGraphics
import Foundation

/// WebP through the embedded ffmpeg's libwebp, since ImageIO cannot encode
/// it: the image goes through a temporary PNG. Metadata is not carried over.
enum WebPEncoder {
    static func encode(_ image: CGImage, quality: Int, to url: URL, with ffmpeg: FFmpegRunner) async throws {
        let png = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        try ImageConverter.write(image, as: .png, to: png)
        do {
            try await ffmpeg.convert(["-i", png.path, "-c:v", "libwebp", "-quality", String(quality), url.path],
                                     duration: nil) { _ in }
        } catch let error as FFmpegError {
            throw OperationError.writeFailed.withDetail(error.description)
        }
    }
}
