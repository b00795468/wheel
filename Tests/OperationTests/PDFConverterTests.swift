import PDFKit
import XCTest

final class PDFConverterTests: XCTestCase {
    func testImagesBecomeOnePDFInDragOrder() throws {
        let dir = try Fixtures.directory(for: self)
        let wide = try Fixtures.writeImage("a.png", in: dir, type: .png, width: 40, height: 20)
        let tall = try Fixtures.writeImage("b.jpg", in: dir, type: .jpeg, width: 20, height: 40)
        let output = dir.appending(path: "out.pdf")
        var steps: [Double] = []

        try PDFConverter.makePDF(from: [wide, tall], destination: output) { steps.append($0) }

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 40, height: 20))
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 20, height: 40))
        XCTAssertEqual(steps, [0.5, 1])
    }

    func testPageSizeFollowsTheImageResolution() throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("scan.png", in: dir, type: .png, width: 600, height: 300, dpi: 300)
        let output = dir.appending(path: "out.pdf")

        try PDFConverter.makePDF(from: [input], destination: output) { _ in }

        XCTAssertEqual(PDFDocument(url: output)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 144, height: 72))
    }

    func testSinglePagePDFGivesOneImageAt300DPI() throws {
        let dir = try Fixtures.directory(for: self)
        let pdf = try Fixtures.writePDF("a4.pdf", in: dir, pages: [CGSize(width: 595, height: 842)])
        let out = dir.appending(path: "out", directoryHint: .isDirectory)

        let result = try PDFConverter.renderPages(of: pdf, as: .png, output: OutputLocator(destination: .custom(out))) { _ in }

        XCTAssertEqual(result.lastPathComponent, "a4.png")
        let info = try Fixtures.info(result)
        XCTAssertEqual([info.width, info.height], [2479, 3508])
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(info.image, x: 20, y: 20)))
        XCTAssertTrue(Fixtures.isWhite(Fixtures.pixel(info.image, x: 1200, y: 1700)))
    }

    func testMultiPagePDFGivesAFolderOfNumberedPages() throws {
        let dir = try Fixtures.directory(for: self)
        let pdf = try Fixtures.writePDF("doc.pdf", in: dir, pages: Array(repeating: CGSize(width: 100, height: 100), count: 12))
        let out = dir.appending(path: "out", directoryHint: .isDirectory)

        let folder = try PDFConverter.renderPages(of: pdf, as: .jpeg, output: OutputLocator(destination: .custom(out))) { _ in }

        XCTAssertEqual(folder.lastPathComponent, "doc")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names.count, 12)
        XCTAssertEqual(names.first, "doc 01.jpg")
        XCTAssertEqual(names.last, "doc 12.jpg")
    }

    func testRotatedPageIsRenderedUpright() throws {
        let dir = try Fixtures.directory(for: self)
        // 200×100 pt page, red square top-left, displayed rotated 90° clockwise.
        let pdf = try Fixtures.writePDF("r.pdf", in: dir, pages: [CGSize(width: 200, height: 100)], rotations: [90])
        let out = dir.appending(path: "out", directoryHint: .isDirectory)

        let image = try Fixtures.info(try PDFConverter.renderPages(of: pdf, as: .png,
                                                                   output: OutputLocator(destination: .custom(out))) { _ in })

        XCTAssertEqual([image.width, image.height], [417, 833])
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(image.image, x: image.width - 20, y: 20)), "top-left goes top-right")
    }

    func testLockedAndCorruptPDFsThrowHumanErrors() throws {
        let dir = try Fixtures.directory(for: self)
        let locked = try Fixtures.writePDF("locked.pdf", in: dir, pages: [CGSize(width: 100, height: 100)], password: "secret")
        let corrupt = dir.appending(path: "corrupt.pdf")
        try Data("not a pdf".utf8).write(to: corrupt)
        let locator = OutputLocator(destination: .custom(dir.appending(path: "out")))

        XCTAssertThrowsError(try PDFConverter.renderPages(of: locked, as: .png, output: locator) { _ in }) {
            XCTAssertEqual($0 as? OperationError, .lockedPDF)
        }
        XCTAssertThrowsError(try PDFConverter.renderPages(of: corrupt, as: .png, output: locator) { _ in }) {
            XCTAssertEqual($0 as? OperationError, .unreadablePDF)
        }
    }
}
