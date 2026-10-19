import XCTest

final class MediaConvertOperationTests: XCTestCase {
    private func context(_ dir: URL) throws -> OperationContext {
        OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))),
                         stripsLocation: false, ffmpeg: try Fixtures.ffmpeg())
    }

    private func convert(_ input: URL, to output: MediaOutput, in dir: URL) async throws -> URL {
        let outputs = try await MediaConvertOperation(output: output).run(inputs: [input], context: try context(dir)) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    func testHEVCBecomesH264InMP4() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mov", in: dir, codec: "hevc_videotoolbox")

        let output = try await convert(input, to: .mp4, in: dir)

        XCTAssertEqual(output.lastPathComponent, "clip.mp4")
        XCTAssertEqual(try Fixtures.codecs(of: output), ["h264", "aac"])
    }

    func testH264IsRewrappedIntoMOV() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir)

        let output = try await convert(input, to: .mov, in: dir)

        XCTAssertEqual(try Fixtures.codecs(of: output), ["h264", "aac"])
    }

    func testVideoToGIFIsAtMost720Wide() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir, size: "1280x720")

        let output = try await convert(input, to: .gif, in: dir)

        XCTAssertEqual(try Fixtures.codecs(of: output), ["gif"])
        XCTAssertEqual(try Fixtures.info(output).width, 720)
    }

    func testSoundtrackAndAudioConversions() async throws {
        let dir = try Fixtures.directory(for: self)
        let video = try Fixtures.writeVideo("clip.mp4", in: dir)
        let wav = try Fixtures.writeAudio("tone.wav", in: dir)

        let mp3 = try await convert(video, to: .mp3, in: dir)
        let m4a = try await convert(video, to: .m4a, in: dir)
        let flac = try await convert(wav, to: .flac, in: dir)
        let backToWAV = try await convert(flac, to: .wav, in: dir)

        XCTAssertEqual(try Fixtures.codecs(of: mp3), ["mp3"])
        XCTAssertEqual(try Fixtures.codecs(of: m4a), ["aac"])
        XCTAssertEqual(try Fixtures.codecs(of: flac), ["flac"])
        XCTAssertEqual(try Fixtures.codecs(of: backToWAV), ["pcm_s16le"])
    }

    func testSilentVideoToMP3FailsWithAHumanMessage() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("silent.mp4", in: dir, audio: false)

        do {
            _ = try await convert(input, to: .mp3, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .noAudio)
        }
    }

    func testCorruptVideoFailsWithAHumanMessageAndADetail() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = dir.appending(path: "bad.mp4")
        try Data("not a video".utf8).write(to: input)

        do {
            _ = try await convert(input, to: .mov, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .unreadableVideo)
            XCTAssertNotNil(error.detail)
        }
    }

    func testMissingEngineIsReported() async throws {
        let dir = try Fixtures.directory(for: self)
        let context = OperationContext(output: OutputLocator(destination: .custom(dir)), stripsLocation: false)

        do {
            _ = try await MediaConvertOperation(output: .mp3).run(inputs: [dir.appending(path: "a.wav")], context: context) { _ in }
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .engineMissing)
        }
    }

    func testImageToWebP() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("logo.png", in: dir, type: .png, alpha: true)

        let outputs = try await ImageToWebPOperation().run(inputs: [input], context: try context(dir)) { _ in }

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["logo.webp"])
        let info = try Fixtures.info(outputs[0])
        XCTAssertEqual(info.type, "org.webmproject.webp")
        XCTAssertEqual([info.width, info.height], [40, 20])
    }
}
