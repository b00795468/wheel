import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Writes an image back in the format of the file it came from, since the
/// tools keep formats: ImageIO for most, the embedded ffmpeg for WebP.
enum ImageRewriter {
    static func canRewrite(_ type: UTType) -> Bool {
        type.conforms(to: .webP) || ImageFormat.matching(type) != nil
    }

    /// `quality` applies to lossy formats only (nil: the format's default).
    static func write(_ image: CGImage, like type: UTType, to url: URL, quality: Double?,
                      properties: [CFString: Any], ffmpeg: FFmpegRunner?) async throws {
        if type.conforms(to: .webP) {
            guard let ffmpeg else { throw OperationError.engineMissing }
            let percent = Int(((quality ?? 0.9) * 100).rounded())
            try await WebPEncoder.encode(image, quality: percent, to: url, with: ffmpeg)
            return
        }
        guard var format = ImageFormat.matching(type) else { throw OperationError.unreadableImage }
        if let quality { format = format.withQuality(quality) }
        try ImageConverter.write(image, as: format, to: url, properties: properties)
    }
}
