import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

final class CompressOperationTests: XCTestCase {
    private func context(_ dir: URL, ffmpeg: Bool = true) throws -> OperationContext {
        OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))), stripsLocation: false,
                         ffmpeg: ffmpeg ? try Fixtures.ffmpeg() : nil)
    }

    private func compress(_ input: URL, in dir: URL) async throws -> URL {
        let outputs = try await CompressOperation().run(inputs: [input], context: try context(dir)) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    func testJPEGIsReencodedSmallerWithTheSuffix() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeNoiseImage("photo.jpg", in: dir, type: .jpeg)

        let output = try await compress(input, in: dir)

        XCTAssertEqual(output.lastPathComponent, "photo (compressé).jpg")
        XCTAssertLessThan(try size(output), try size(input))
        let info = try Fixtures.info(output)
        XCTAssertEqual(info.type, UTType.jpeg.identifier)
        XCTAssertEqual([info.width, info.height], [400, 300])
    }

    func testHEICAndWebPKeepTheirFormat() async throws {
        let dir = try Fixtures.directory(for: self)
        let heic = try Fixtures.writeNoiseImage("a.heic", in: dir, type: .heic)
        let webp = dir.appending(path: "b.webp")
        try await WebPEncoder.encode(Fixtures.makeNoiseImage(width: 400, height: 300), quality: 100, to: webp,
                                     with: try Fixtures.ffmpeg())

        let compressedHEIC = try await compress(heic, in: dir)
        let compressedWebP = try await compress(webp, in: dir)

        XCTAssertEqual(try Fixtures.info(compressedHEIC).type, UTType.heic.identifier)
        XCTAssertEqual(try Fixtures.info(compressedWebP).type, UTType.webP.identifier)
        XCTAssertLessThan(try size(compressedWebP), try size(webp))
    }

    func testTIFFGetsLosslessLZW() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("scan.tiff", in: dir, type: .tiff, width: 400, height: 300)

        let output = try await compress(input, in: dir)

        XCTAssertLessThan(try size(output), try size(input))
        let tiff = try Fixtures.info(output).properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFCompression] as? Int, 5)
    }

    func testAFileThatWouldNotShrinkIsRefusedAndNothingIsWritten() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeNoiseImage("noise.png", in: dir, type: .png)

        do {
            _ = try await compress(input, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .alreadyCompressed)
        }
        let out = dir.appending(path: "out")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? [], [])
    }

    func testPDFImagesAreDownsampled() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImagePDF("scan.pdf", in: dir)

        let output = try await compress(input, in: dir)

        XCTAssertEqual(output.lastPathComponent, "scan (compressé).pdf")
        XCTAssertLessThan(try size(output), try size(input))
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
        XCTAssertEqual(PDFDocument(url: output)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 400, height: 300))
    }

    func testVideoBecomesHEVCAtMost1080p() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir, seconds: 2, size: "3840x2160", quality: "80")

        let output = try await compress(input, in: dir)

        XCTAssertEqual(output.lastPathComponent, "clip (compressé).mp4")
        XCTAssertLessThan(try size(output), try size(input))
        XCTAssertEqual(try Fixtures.codecs(of: output), ["hevc", "aac"])
        let probe = try await Fixtures.ffmpeg().probe(output)
        XCTAssertEqual(probe.width, 1920)
        XCTAssertEqual(probe.height, 1080)
    }

    func testAcceptedTypes() {
        let operation = CompressOperation()
        func type(_ ext: String) -> UTType { UTType(filenameExtension: ext)! }
        for ext in ["jpg", "png", "heic", "tiff", "webp", "avif", "pdf", "mov", "mkv"] {
            XCTAssertTrue(operation.accepts([type(ext)]), ext)
        }
        for ext in ["bmp", "mp3", "wav", "txt"] {
            XCTAssertFalse(operation.accepts([type(ext)]), ext)
        }
        XCTAssertFalse(operation.accepts([.folder]))
    }

    func testRotatedPDFPagesStayUpright() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImagePDF("rotated.pdf", in: dir, rotation: 90)

        let output = try await compress(input, in: dir)
        let page = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0))

        XCTAssertEqual(page.rotation, 0)
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 300, height: 400))
    }
}
