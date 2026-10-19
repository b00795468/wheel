import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

/// Test files generated in code, so the suite needs no checked-in binaries.
enum Fixtures {
    struct ImageInfo {
        let type: String
        let width: Int
        let height: Int
        let properties: [CFString: Any]
        let image: CGImage
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    private static let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// Fresh empty folder, deleted when the test ends.
    static func directory(for test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PivotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Blue image (transparent when `alpha`) with a red 10×10 block in its
    /// top-left corner, to check orientation after conversion.
    static func makeCGImage(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: info.rawValue)!
        let all = CGRect(x: 0, y: 0, width: width, height: height)
        if alpha {
            context.clear(all)
        } else {
            context.setFillColor(blue)
            context.fill(all)
        }
        context.setFillColor(red)
        context.fill(CGRect(x: 0, y: height - 10, width: 10, height: 10))
        return context.makeImage()!
    }

    @discardableResult
    static func writeImage(_ name: String, in directory: URL, type: UTType, width: Int = 40, height: Int = 20,
                           alpha: Bool = false, orientation: Int = 1, gps: Bool = false, dpi: Double? = nil) throws -> URL {
        let url = directory.appending(path: name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 48.85, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.35, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(destination, makeCGImage(width: width, height: height, alpha: alpha),
                                   properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// PDF whose pages have the given sizes (points), each with a red
    /// 50×50 square in its top-left corner. `rotations` applies per page.
    @discardableResult
    static func writePDF(_ name: String, in directory: URL, pages: [CGSize], rotations: [Int] = [],
                         password: String? = nil) throws -> URL {
        let data = NSMutableData()
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: nil, nil)!
        for size in pages {
            var box = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &box)
            context.setFillColor(red)
            context.fill(CGRect(x: 0, y: size.height - 50, width: 50, height: 50))
            context.endPage()
        }
        context.closePDF()

        let document = PDFDocument(data: data as Data)!
        for (index, rotation) in rotations.enumerated() {
            document.page(at: index)?.rotation = rotation
        }
        var options: [PDFDocumentWriteOption: Any] = [:]
        if let password {
            options[.userPasswordOption] = password
            options[.ownerPasswordOption] = password
        }
        let url = directory.appending(path: name)
        guard document.write(to: url, withOptions: options) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func info(_ url: URL) throws -> ImageInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return ImageInfo(type: type, width: image.width, height: image.height, properties: properties, image: image)
    }

    /// RGBA of the pixel at (x, y), counted from the top-left corner.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let flippedY = image.height - 1 - y
            context.draw(image, in: CGRect(x: -x, y: -flippedY, width: image.width, height: image.height))
        }
        return data
    }

    static func isRed(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] < 70 && pixel[2] < 70 }
    static func isWhite(_ pixel: [UInt8]) -> Bool { pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240 }
}
