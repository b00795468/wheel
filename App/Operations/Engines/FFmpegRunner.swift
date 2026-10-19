import Foundation

/// What ffprobe reports about a media file.
struct MediaProbe: Equatable, Sendable {
    var duration: Double?
    /// Codec of the first real video stream (cover art excluded), e.g. "h264".
    var videoCodec: String?
    var audioCodec: String?
    /// Coded size of that video stream.
    var width: Int? = nil
    var height: Int? = nil

    /// Parses `ffprobe -show_entries format=duration:stream=codec_type,codec_name,width,height:stream_disposition=attached_pic -of json`.
    static func parse(_ json: Data) throws -> MediaProbe {
        struct Output: Decodable {
            struct Stream: Decodable {
                let codecType: String?
                let codecName: String?
                let width: Int?
                let height: Int?
                let disposition: [String: Int]?
            }
            struct Format: Decodable {
                let duration: String?
            }
            let streams: [Stream]?
            let format: Format?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(Output.self, from: json)
        let streams = output.streams ?? []
        let video = streams.first { $0.codecType == "video" && $0.disposition?["attached_pic"] != 1 }
        let audio = streams.first { $0.codecType == "audio" }
        let duration = output.format?.duration.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        return MediaProbe(duration: duration, videoCodec: video?.codecName, audioCodec: audio?.codecName,
                          width: video?.width, height: video?.height)
    }
}

/// ffmpeg or ffprobe exited with an error; `log` is the end of its stderr.
struct FFmpegError: Error, CustomStringConvertible {
    let status: Int32
    let log: String
    var description: String { "exit \(status): \(log)" }
}

/// Runs the embedded ffmpeg / ffprobe (§3): duration from ffprobe, progress
/// from `-progress pipe:1`, cancellation by terminating the process.
struct FFmpegRunner: Sendable {
    let ffmpeg: URL
    let ffprobe: URL

    /// Binaries copied into Contents/Resources/bin by the "Embed ffmpeg" build phase.
    static var bundled: FFmpegRunner? {
        guard let bin = Bundle.main.resourceURL?.appending(path: "bin") else { return nil }
        let runner = FFmpegRunner(ffmpeg: bin.appending(path: "ffmpeg"), ffprobe: bin.appending(path: "ffprobe"))
        return runner.isAvailable ? runner : nil
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpeg.path)
            && FileManager.default.isExecutableFile(atPath: ffprobe.path)
    }

    func probe(_ input: URL) async throws -> MediaProbe {
        let result = try await Self.execute(ffprobe, [
            "-v", "error",
            "-show_entries", "format=duration:stream=codec_type,codec_name,width,height:stream_disposition=attached_pic",
            "-of", "json", input.path,
        ])
        guard result.status == 0 else { throw FFmpegError(status: result.status, log: result.log) }
        return try MediaProbe.parse(result.output)
    }

    /// Runs ffmpeg with `arguments` (input, codecs, output path). Progress is
    /// reported against `duration` when it is known.
    func convert(_ arguments: [String], duration: Double?,
                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let prefix = "out_time_us="
        let base = ["-hide_banner", "-nostdin", "-nostats", "-loglevel", "error", "-progress", "pipe:1", "-y"]
        let result = try await Self.execute(ffmpeg, base + arguments) { line in
            guard let duration, duration > 0, line.hasPrefix(prefix),
                  let microseconds = Double(line.dropFirst(prefix.count)) else { return }
            progress(min(max(microseconds / (duration * 1_000_000), 0), 1))
        }
        guard result.status == 0 else { throw FFmpegError(status: result.status, log: result.log) }
    }

    // MARK: Process

    private struct Result {
        let status: Int32
        let output: Data
        let log: String
    }

    /// Lets the cancellation handler reach the process.
    private final class ProcessBox: @unchecked Sendable {
        /// SIGTERM lets ffmpeg finish the frame it is encoding, which can take
        /// seconds on a busy machine; past this grace it is killed outright.
        private static let killGrace: TimeInterval = 0.5

        let process = Process()

        func stop() {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGrace) { [process] in
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    /// Launches `executable` and waits for it. Cancelling the task terminates it.
    private static func execute(_ executable: URL, _ arguments: [String],
                                onLine: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        let box = ProcessBox()
        let process = box.process
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let collector = OutputCollector(onLine: onLine)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collector.appendOutput(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collector.appendLog(data) }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                // Cancelled before the process existed: the handler could not stop it.
                if Task.isCancelled { box.stop() }
            }
        } onCancel: {
            box.stop()
        }

        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        collector.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
        collector.appendLog(errors.fileHandleForReading.readDataToEndOfFile())
        try Task.checkCancellation()
        return Result(status: process.terminationStatus, output: collector.output, log: collector.log)
    }
}

/// Accumulates a process's output from pipe callbacks on background threads.
private final class OutputCollector: @unchecked Sendable {
    /// Only the end of stderr is kept, for the technical log.
    private static let maxLogBytes = 16_384

    private let lock = NSLock()
    private let onLine: (@Sendable (String) -> Void)?
    private var stdout = Data()
    private var pendingLine = Data()
    private var stderr = Data()

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    var output: Data { lock.withLock { stdout } }
    var log: String { lock.withLock { String(decoding: stderr, as: UTF8.self) } }

    func appendOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [String] = lock.withLock {
            stdout.append(data)
            pendingLine.append(data)
            var lines: [String] = []
            while let newline = pendingLine.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: pendingLine[pendingLine.startIndex..<newline], as: UTF8.self))
                pendingLine.removeSubrange(pendingLine.startIndex...newline)
            }
            return lines
        }
        if let onLine { lines.forEach(onLine) }
    }

    func appendLog(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            stderr.append(data)
            if stderr.count > Self.maxLogBytes { stderr = stderr.suffix(Self.maxLogBytes) }
        }
    }
}
