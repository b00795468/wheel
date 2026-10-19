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

    static let jpeg = ImageFormat(type: .jpeg, fileExtension: "jpg", title: "JPG", symbol: "",
                                  supportsAlpha: false, lossyQuality: 0.9, sameFormatTypes: [.jpeg])
    static let png = ImageFormat(type: .png, fileExtension: "png", title: "PNG", symbol: "",
                                 supportsAlpha: true, lossyQuality: nil, sameFormatTypes: [.png])
    static let heic = ImageFormat(type: .heic, fileExtension: "heic", title: "HEIC", symbol: "",
                                  supportsAlpha: true, lossyQuality: 0.9, sameFormatTypes: [.heic, .heif])
    static let tiff = ImageFormat(type: .tiff, fileExtension: "tiff", title: "TIFF", symbol: "",
                                  supportsAlpha: true, lossyQuality: nil, sameFormatTypes: [.tiff])
    static let avif = ImageFormat(type: FileTypes.avif, fileExtension: "avif", title: "AVIF", symbol: "",
                                  supportsAlpha: true, lossyQuality: 0.9, sameFormatTypes: [FileTypes.avif])
    static let bmp = ImageFormat(type: .bmp, fileExtension: "bmp", title: "BMP", symbol: "",
                                 supportsAlpha: false, lossyQuality: nil, sameFormatTypes: [.bmp])

    /// The ImageIO format of a file of `type`, to write it back as it was.
    static func matching(_ type: UTType) -> ImageFormat? {
        [jpeg, png, heic, tiff, avif, bmp].first { $0.isSameFormat(as: type) }
    }

    /// Same format with another lossy quality; lossless formats are unchanged.
    func withQuality(_ quality: Double) -> ImageFormat {
        ImageFormat(type: type, fileExtension: fileExtension, title: title, symbol: symbol, supportsAlpha: supportsAlpha,
                    lossyQuality: lossyQuality == nil ? nil : quality, sameFormatTypes: sameFormatTypes)
    }
}
