import UniformTypeIdentifiers
import XCTest

final class ResizeOperationTests: XCTestCase {
    private func context(_ dir: URL) throws -> OperationContext {
        OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))), stripsLocation: false,
                         ffmpeg: try Fixtures.ffmpeg())
    }

    private func resize(_ input: URL, _ preset: ResizePreset, in dir: URL) async throws -> URL {
        let outputs = try await ResizeOperation(preset: preset).run(inputs: [input], context: try context(dir)) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    func testPresetArithmetic() {
        XCTAssertEqual(ResizePreset.half.targetLongSide(width: 1600, height: 1200), 800)
        XCTAssertEqual(ResizePreset.long1280.targetLongSide(width: 1600, height: 1200), 1280)
        XCTAssertEqual(ResizePreset.long800.targetLongSide(width: 1200, height: 1600), 800)
        XCTAssertNil(ResizePreset.long1920.targetLongSide(width: 1600, height: 1200), "never enlarge")
        XCTAssertEqual(ResizePreset.allCases.map(\.title), ["50\u{202F}%", "1920\u{00A0}px", "1280\u{00A0}px", "800\u{00A0}px"])
        XCTAssertEqual(ResizePreset.allCases.map(\.fileSuffix), ["50 %", "1920 px", "1280 px", "800 px"])
    }

    func testHalfAnImage() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("shot.png", in: dir, type: .png, width: 400, height: 300)

        let output = try await resize(input, .half, in: dir)

        XCTAssertEqual(output.lastPathComponent, "shot (50 %).png")
        let info = try Fixtures.info(output)
        XCTAssertEqual(info.type, UTType.png.identifier)
        XCTAssertEqual([info.width, info.height], [200, 150])
    }

    func testLongestSidePresetKeepsRatioAndOrientation() async throws {
        let dir = try Fixtures.directory(for: self)
        let landscape = try Fixtures.writeImage("big.jpg", in: dir, type: .jpeg, width: 1600, height: 1200)
        // Stored 1600×1200, shown rotated (portrait 1200×1600).
        let portrait = try Fixtures.writeImage("phone.jpg", in: dir, type: .jpeg, width: 1600, height: 1200, orientation: 6)

        let resizedLandscape = try await resize(landscape, .long800, in: dir)
        let resizedPortrait = try await resize(portrait, .long800, in: dir)

        XCTAssertEqual(resizedLandscape.lastPathComponent, "big (800 px).jpg")
        let landscapeInfo = try Fixtures.info(resizedLandscape)
        let portraitInfo = try Fixtures.info(resizedPortrait)
        XCTAssertEqual([landscapeInfo.width, landscapeInfo.height], [800, 600])
        XCTAssertEqual([portraitInfo.width, portraitInfo.height], [600, 800])
    }

    func testAnImageIsNeverEnlarged() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("small.png", in: dir, type: .png, width: 400, height: 300)

        do {
            _ = try await resize(input, .long1920, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .alreadySmall(than: ResizePreset.long1920.title))
        }
    }

    func testWebPIsResizedAsWebP() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = dir.appending(path: "logo.webp")
        try await WebPEncoder.encode(Fixtures.makeNoiseImage(width: 400, height: 300), quality: 90, to: input,
                                     with: try Fixtures.ffmpeg())

        let info = try Fixtures.info(try await resize(input, .half, in: dir))

        XCTAssertEqual(info.type, UTType.webP.identifier)
        XCTAssertEqual([info.width, info.height], [200, 150])
    }

    func testVideoPresets() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir, size: "1280x720")

        let half = try await resize(input, .half, in: dir)
        let small = try await resize(input, .long800, in: dir)
        let halfProbe = try await Fixtures.ffmpeg().probe(half)
        let smallProbe = try await Fixtures.ffmpeg().probe(small)

        XCTAssertEqual(half.lastPathComponent, "clip (50 %).mp4")
        XCTAssertEqual([halfProbe.width, halfProbe.height], [640, 360])
        XCTAssertEqual([smallProbe.width, smallProbe.height], [800, 450])
        XCTAssertEqual(smallProbe.videoCodec, "h264")
        do {
            _ = try await resize(input, .long1920, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .alreadySmall(than: ResizePreset.long1920.title))
        }
    }
}
