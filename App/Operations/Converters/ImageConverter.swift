import CoreGraphics
import Foundation
import ImageIO

/// Image decoding and encoding with ImageIO (§3).
enum ImageConverter {
    /// Converts the first image of `input` to `format` at `destination`.
    static func convert(_ input: URL, to format: ImageFormat, destination: URL, stripsLocation: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = uprightImage(from: source) else {
            throw OperationError.unreadableImage
        }
        try write(image, as: format, to: destination,
                  properties: metadata(of: source, stripsLocation: stripsLocation))
    }

    /// Encodes `image`, flattening transparency on white for formats without alpha.
    static func write(_ image: CGImage, as format: ImageFormat, to destination: URL,
                      properties: [CFString: Any] = [:]) throws {
        let image = format.supportsAlpha ? image : (flattenedOnWhite(image) ?? image)
        var properties = properties
        if let quality = format.lossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL,
                                                           format.type.identifier as CFString, 1, nil) else {
            throw OperationError.writeFailed
        }
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw OperationError.writeFailed }
    }

    /// First image of `source` with its EXIF orientation applied to the
    /// pixels, so every output (PDF included) shows it the right way up.
    static func uprightImage(from source: CGImageSource) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        guard orientation != 1 else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }

        // The thumbnail API is the ImageIO way to apply the orientation;
        // asking for the full size makes it a full-resolution decode.
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// First image, upright, downscaled so that its longer side is `maxPixelSize`.
    static func downscaledImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Metadata worth keeping (EXIF, IPTC, TIFF, GPS, resolution), with the
    /// orientation reset since `uprightImage` already applied it.
    static func metadata(of source: CGImageSource, stripsLocation: Bool) -> [CFString: Any] {
        let all = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let keys = [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyGPSDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
        var kept: [CFString: Any] = [:]
        for key in keys {
            kept[key] = all[key]
        }
        kept[kCGImagePropertyOrientation] = 1
        if var tiff = kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            kept[kCGImagePropertyTIFFDictionary] = tiff
        }
        if stripsLocation {
            kept[kCGImagePropertyGPSDictionary] = nil
        }
        return kept
    }

    /// Composites `image` over white; JPEG would otherwise turn transparency black.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
