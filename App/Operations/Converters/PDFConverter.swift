import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// PDF reading and writing with PDFKit and Core Graphics (§3).
enum PDFConverter {
    static let renderDPI: CGFloat = 300
    /// Cap for very large pages (posters, plans), in pixels per side.
    static let maxRenderSide: CGFloat = 12_000

    /// One PDF with a page per image, in the given (drag) order.
    static func makePDF(from images: [URL], destination: URL, progress: (Double) -> Void) throws {
        guard let context = CGContext(destination as CFURL, mediaBox: nil, nil) else {
            throw OperationError.writeFailed
        }
        defer { context.closePDF() }
        for (index, url) in images.enumerated() {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = ImageConverter.uprightImage(from: source) else {
                throw OperationError.unreadableImage
            }
            var box = CGRect(origin: .zero, size: pageSize(of: image, source: source))
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
            progress(Double(index + 1) / Double(images.count))
        }
    }

    /// Page size in points from the image's own resolution (72 dpi if unknown).
    static func pageSize(of image: CGImage, source: CGImageSource) -> CGSize {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        return CGSize(width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
    }

    static func openDocument(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw OperationError.unreadablePDF }
        if document.isLocked { throw OperationError.lockedPDF }
        guard document.pageCount > 0 else { throw OperationError.unreadablePDF }
        return document
    }

    /// Renders a page on white at `renderDPI`, honouring its crop box and rotation.
    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let quarterTurn = (page.rotation / 90) % 2 != 0
        let size = quarterTurn ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min(renderDPI / 72, maxRenderSide / max(size.width, size.height, 1))
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }

    /// Renders every page of `pdf` as `format`: one file for a single page,
    /// otherwise a folder "<name>/<name> 01.png", "<name> 02.png"… (§5.4).
    static func renderPages(of pdf: URL, as format: ImageFormat, output: OutputLocator,
                            progress: (Double) -> Void) throws -> URL {
        let document = try openDocument(pdf)
        let base = pdf.baseName
        let count = document.pageCount
        let resolution: [CFString: Any] = [kCGImagePropertyDPIWidth: renderDPI, kCGImagePropertyDPIHeight: renderDPI]

        func writePage(_ index: Int, named name: String, with locator: OutputLocator) throws -> URL {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let image = render(page) else {
                throw OperationError.unreadablePDF
            }
            let url = try locator.commit(baseName: name, fileExtension: format.fileExtension, for: pdf) {
                try ImageConverter.write(image, as: format, to: $0, properties: resolution)
            }
            progress(Double(index + 1) / Double(count))
            return url
        }

        if count == 1 {
            return try writePage(0, named: base, with: output)
        }
        let folder = try output.makeFolder(baseName: base, for: pdf)
        let pages = OutputLocator(destination: .custom(folder))
        let digits = String(count).count
        do {
            for index in 0..<count {
                let number = String(index + 1)
                let padded = String(repeating: "0", count: digits - number.count) + number
                _ = try writePage(index, named: "\(base) \(padded)", with: pages)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }
}
