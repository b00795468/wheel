import Foundation
import UniformTypeIdentifiers

/// An output image format ImageIO can encode natively (§3). WebP is not
/// one: ImageIO cannot encode it, it comes with the embedded ffmpeg (phase 4).
struct ImageFormat: Equatable, Sendable {
    let type: UTType
    let fileExtension: String
    let title: String
    let symbol: String
    let supportsAlpha: Bool
    /// Encoder quality for lossy formats, nil for lossless ones.
    let lossyQuality: Double?
    /// Input types that already are this format: no X → X conversion (§5.4).
    let sameFormatTypes: [UTType]

    func isSameFormat(as input: UTType) -> Bool {
        sameFormatTypes.contains { input.conforms(to: $0) }
    }

    static let jpeg = ImageFormat(type: .jpeg, fileExtension: "jpg", title: "JPG", symbol: "photo",
                                  supportsAlpha: false, lossyQuality: 0.9, sameFormatTypes: [.jpeg])
    static let png = ImageFormat(type: .png, fileExtension: "png", title: "PNG", symbol: "photo.fill",
                                 supportsAlpha: true, lossyQuality: nil, sameFormatTypes: [.png])
    static let heic = ImageFormat(type: .heic, fileExtension: "heic", title: "HEIC", symbol: "photo.on.rectangle",
                                  supportsAlpha: true, lossyQuality: 0.9, sameFormatTypes: [.heic, .heif])
    static let tiff = ImageFormat(type: .tiff, fileExtension: "tiff", title: "TIFF", symbol: "doc.richtext",
                                  supportsAlpha: true, lossyQuality: nil, sameFormatTypes: [.tiff])
}
