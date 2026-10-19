import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ImageConverterTests: XCTestCase {
    private func convert(_ input: URL, to format: ImageFormat, stripsLocation: Bool = false) throws -> URL {
        let output = input.deletingLastPathComponent()
            .appending(path: "out-\(UUID().uuidString).\(format.fileExtension)")
        try ImageConverter.convert(input, to: format, destination: output, stripsLocation: stripsLocation)
        return output
    }

    func testEachFormatIsWrittenWithItsRealType() throws {
        let dir = try Fixtures.directory(for: self)
        let png = try Fixtures.writeImage("a.png", in: dir, type: .png)
        let jpg = try Fixtures.writeImage("b.jpg", in: dir, type: .jpeg)
        for (input, format) in [(png, ImageFormat.jpeg), (png, .heic), (png, .tiff), (jpg, .png)] {
            let info = try Fixtures.info(try convert(input, to: format))
            XCTAssertEqual(info.type, format.type.identifier, format.title)
            XCTAssertEqual([info.width, info.height], [40, 20], format.title)
        }
    }

    func testAVIFAndBMPInputsAreRead() throws {
        let dir = try Fixtures.directory(for: self)
        for (name, type) in [("a.avif", FileTypes.avif), ("a.bmp", UTType.bmp)] {
            let input = try Fixtures.writeImage(name, in: dir, type: type)
            XCTAssertEqual(try Fixtures.info(try convert(input, to: .png)).type, UTType.png.identifier, name)
        }
    }

    func testOrientationIsAppliedToThePixels() throws {
        let dir = try Fixtures.directory(for: self)
        // Stored 40×20 with red top-left; orientation 6 = shown rotated 90° clockwise.
        let input = try Fixtures.writeImage("rotated.jpg", in: dir, type: .jpeg, orientation: 6)

        let info = try Fixtures.info(try convert(input, to: .png))

        XCTAssertEqual([info.width, info.height], [20, 40])
        XCTAssertEqual(info.properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(info.image, x: 17, y: 2)), "red block should now be top-right")
    }

    func testTransparencyBecomesWhiteInJPEG() throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("alpha.png", in: dir, type: .png, alpha: true)

        let info = try Fixtures.info(try convert(input, to: .jpeg))

        XCTAssertTrue(Fixtures.isWhite(Fixtures.pixel(info.image, x: 30, y: 15)))
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(info.image, x: 3, y: 3)))
    }

    func testLocationIsKeptByDefaultAndStrippedOnRequest() throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("gps.jpg", in: dir, type: .jpeg, gps: true)

        let kept = try Fixtures.info(try convert(input, to: .heic))
        let stripped = try Fixtures.info(try convert(input, to: .heic, stripsLocation: true))

        XCTAssertNotNil(kept.properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(stripped.properties[kCGImagePropertyGPSDictionary])
    }

    func testUnreadableImageThrowsAHumanError() throws {
        let dir = try Fixtures.directory(for: self)
        let input = dir.appending(path: "bad.jpg")
        try Data("not an image".utf8).write(to: input)

        XCTAssertThrowsError(try convert(input, to: .png)) { error in
            XCTAssertEqual(error as? OperationError, .unreadableImage)
        }
    }
}
