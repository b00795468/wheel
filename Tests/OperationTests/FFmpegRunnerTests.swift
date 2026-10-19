import XCTest

final class FFmpegRunnerTests: XCTestCase {
    func testProbeJSONIsParsed() throws {
        let json = #"{"streams":[{"codec_name":"h264","codec_type":"video","disposition":{"attached_pic":0}},{"codec_name":"aac","codec_type":"audio","disposition":{"attached_pic":0}}],"format":{"duration":"3.000000"}}"#
        XCTAssertEqual(try MediaProbe.parse(Data(json.utf8)),
                       MediaProbe(duration: 3, videoCodec: "h264", audioCodec: "aac"))
    }

    func testCoverArtIsNotAVideoStream() throws {
        let json = #"{"streams":[{"codec_name":"mp3","codec_type":"audio","disposition":{"attached_pic":0}},{"codec_name":"mjpeg","codec_type":"video","disposition":{"attached_pic":1}}],"format":{"duration":"N/A"}}"#
        XCTAssertEqual(try MediaProbe.parse(Data(json.utf8)),
                       MediaProbe(duration: nil, videoCodec: nil, audioCodec: "mp3"))
        XCTAssertThrowsError(try MediaProbe.parse(Data("not json".utf8)))
    }

    func testProbeReadsDurationAndCodecs() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)
        let video = try Fixtures.writeVideo("clip.mp4", in: dir, seconds: 2)

        let probe = try await ffmpeg.probe(video)

        XCTAssertEqual(probe.duration ?? 0, 2, accuracy: 0.2)
        XCTAssertEqual(probe.videoCodec, "h264")
        XCTAssertEqual(probe.audioCodec, "aac")
    }

    func testConvertReportsProgressUpToTheEnd() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)
        let video = try Fixtures.writeVideo("clip.mp4", in: dir, seconds: 4)
        let output = dir.appending(path: "out.mov")
        let recorder = ProgressRecorder()

        try await ffmpeg.convert(["-i", video.path, "-c:v", "h264_videotoolbox", "-an", output.path], duration: 4) {
            recorder.record($0)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(recorder.values.isEmpty)
        XCTAssertEqual(recorder.values, recorder.values.sorted())
        XCTAssertGreaterThan(recorder.last ?? 0, 0.9)
    }

    func testFailureCarriesTheFFmpegLog() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)

        do {
            try await ffmpeg.convert(["-i", dir.appending(path: "missing.mp4").path, dir.appending(path: "o.mp4").path],
                                     duration: nil) { _ in }
            XCTFail("expected a failure")
        } catch let error as FFmpegError {
            XCTAssertNotEqual(error.status, 0)
            XCTAssertFalse(error.log.isEmpty)
        }
    }

    func testCancellationStopsFFmpegQuickly() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)
        let output = dir.appending(path: "long.mp4")
        let task = Task {
            try await ffmpeg.convert(["-f", "lavfi", "-i", "testsrc2=duration=600:size=1920x1080:rate=30",
                                      "-c:v", "libx264", "-preset", "veryslow", output.path], duration: 600) { _ in }
        }
        try await Task.sleep(for: .milliseconds(500))

        let start = Date()
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testProbeReportsTheVideoSize() throws {
        let json = #"{"streams":[{"codec_name":"hevc","codec_type":"video","width":3840,"height":2160,"disposition":{"attached_pic":0}}],"format":{"duration":"1.0"}}"#
        let probe = try MediaProbe.parse(Data(json.utf8))
        XCTAssertEqual(probe.width, 3840)
        XCTAssertEqual(probe.height, 2160)
    }
}
