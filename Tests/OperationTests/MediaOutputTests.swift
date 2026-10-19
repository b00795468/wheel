import XCTest

final class MediaOutputTests: XCTestCase {
    private let h264AAC = MediaProbe(duration: 10, videoCodec: "h264", audioCodec: "aac")
    private let hevcPCM = MediaProbe(duration: 10, videoCodec: "hevc", audioCodec: "pcm_s16le")
    private let audioOnly = MediaProbe(duration: 10, videoCodec: nil, audioCodec: "mp3")
    private let silentVideo = MediaProbe(duration: 10, videoCodec: "h264", audioCodec: nil)

    private func has(_ arguments: [String], _ sequence: [String]) -> Bool {
        arguments.indices.contains { Array(arguments[$0...].prefix(sequence.count)) == sequence }
    }

    func testH264WithAACIsRewrappedWithoutReencoding() throws {
        let arguments = try MediaOutput.mp4.codecArguments(for: h264AAC, allowStreamCopy: true)
        XCTAssertTrue(has(arguments, ["-c:v", "copy"]))
        XCTAssertTrue(has(arguments, ["-c:a", "copy"]))
        XCTAssertTrue(has(arguments, ["-movflags", "+faststart"]))
    }

    func testOtherCodecsAreReencodedWithVideoToolbox() throws {
        for probe in [hevcPCM, h264AAC] {
            let arguments = try MediaOutput.mov.codecArguments(for: probe, allowStreamCopy: probe == hevcPCM)
            XCTAssertTrue(has(arguments, ["-c:v", "h264_videotoolbox", "-q:v", OutputQuality.standard.videoQuality]))
            XCTAssertTrue(has(arguments, ["-c:a", "aac_at", "-b:a", "192k"]))
            XCTAssertFalse(arguments.contains("-movflags"), "faststart is for MP4 only")
        }
    }

    func testGIFUsesAPaletteAt15FPSAndAtMost720Wide() throws {
        let arguments = try MediaOutput.gif.codecArguments(for: h264AAC, allowStreamCopy: true)
        let filter = try XCTUnwrap(arguments.firstIndex(of: "-vf").map { arguments[$0 + 1] })
        XCTAssertTrue(filter.contains("fps=15"))
        XCTAssertTrue(filter.contains("min(720,iw)"))
        XCTAssertTrue(filter.contains("palettegen"))
        XCTAssertTrue(filter.contains("paletteuse"))
        XCTAssertTrue(arguments.contains("-an"))
    }

    func testAudioOutputs() throws {
        XCTAssertTrue(has(try MediaOutput.mp3.codecArguments(for: h264AAC, allowStreamCopy: true),
                          ["-c:a", "libmp3lame", "-b:a", "192k"]))
        XCTAssertTrue(has(try MediaOutput.m4a.codecArguments(for: h264AAC, allowStreamCopy: true), ["-c:a", "copy"]))
        XCTAssertTrue(has(try MediaOutput.m4a.codecArguments(for: audioOnly, allowStreamCopy: true),
                          ["-c:a", "aac_at", "-b:a", "256k"]))
        XCTAssertTrue(has(try MediaOutput.wav.codecArguments(for: audioOnly, allowStreamCopy: true), ["-c:a", "pcm_s16le"]))
        XCTAssertTrue(has(try MediaOutput.flac.codecArguments(for: audioOnly, allowStreamCopy: true), ["-c:a", "flac"]))
        XCTAssertTrue(has(try MediaOutput.mp3.codecArguments(for: audioOnly, allowStreamCopy: true), ["-map", "0:a:0", "-vn"]))
    }

    func testMissingStreamsGiveHumanErrors() {
        XCTAssertThrowsError(try MediaOutput.mp3.codecArguments(for: silentVideo, allowStreamCopy: true)) {
            XCTAssertEqual($0 as? OperationError, .noAudio)
        }
        for output in [MediaOutput.mp4, .gif] {
            XCTAssertThrowsError(try output.codecArguments(for: audioOnly, allowStreamCopy: true)) {
                XCTAssertEqual($0 as? OperationError, .noVideo)
            }
        }
    }

    func testHighQualityRaisesTheVideoQuality() throws {
        let arguments = try MediaOutput.mp4.codecArguments(for: hevcPCM, allowStreamCopy: true, quality: .high)
        XCTAssertTrue(has(arguments, ["-q:v", OutputQuality.high.videoQuality]))
        XCTAssertEqual(OutputQuality.high.videoQuality, "80")
    }
}
