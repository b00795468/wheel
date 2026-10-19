import Foundation
import UniformTypeIdentifiers

/// "To <format>" for audio and video, through the embedded ffmpeg (§5.4).
struct MediaConvertOperation: FileOperation {
    let output: MediaOutput

    var id: String { "convert.\(output.fileExtension)" }
    var kind: WheelMode { .convert }
    var title: String { output.title }
    var symbol: String { output.symbol }
    var usesMediaEngine: Bool { true }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { type in
            let accepted = FileTypes.isVideo(type) ? output.acceptsVideo : FileTypes.isAudio(type) && output.acceptsAudio
            guard accepted else { return false }
            return !output.isSameFormat(as: type)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { progress((Double(index) + $0) / Double(inputs.count)) }
            outputs.append(try await convert(input, with: ffmpeg, context: context, progress: share))
            share(1)
        }
        return outputs
    }

    private func convert(_ input: URL, with ffmpeg: FFmpegRunner, context: OperationContext,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let unreadable: OperationError = FileTypes.isVideo(FileTypes.type(of: input)) ? .unreadableVideo : .unreadableAudio
        let probe: MediaProbe
        do {
            probe = try await ffmpeg.probe(input)
        } catch let error as FFmpegError {
            throw unreadable.withDetail(error.description)
        }
        let rewrap = try output.codecArguments(for: probe, allowStreamCopy: true)
        let reencode = try output.codecArguments(for: probe, allowStreamCopy: false)

        return try await context.output.commitAsync(baseName: input.baseName, fileExtension: output.fileExtension,
                                                    for: input) { temporary in
            let arguments = { (codec: [String]) in ["-i", input.path] + codec + [temporary.path] }
            do {
                try await ffmpeg.convert(arguments(rewrap), duration: probe.duration, progress: progress)
            } catch let error as FFmpegError {
                // A stream copy can fail on unusual sources: retry with a full re-encode.
                guard rewrap != reencode else { throw unreadable.withDetail(error.description) }
                do {
                    try await ffmpeg.convert(arguments(reencode), duration: probe.duration, progress: progress)
                } catch let error as FFmpegError {
                    throw unreadable.withDetail(error.description)
                }
            }
        }
    }
}
