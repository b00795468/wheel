import Foundation
import UniformTypeIdentifiers

/// Audio and video outputs, encoded by the embedded ffmpeg (§5.4).
enum MediaOutput: String, CaseIterable, Sendable {
    case mp4, mov, gif, mp3, m4a, wav, flac

    static let gifFrameRate = 15
    static let gifMaxWidth = 720

    var fileExtension: String { rawValue }
    var title: String { rawValue.uppercased() }

    var symbol: String {
        switch self {
        case .mp4: "film"
        case .mov: "film"
        case .gif: "photo.stack"
        case .mp3, .m4a: "music.note"
        case .wav, .flac: "waveform"
        }
    }

    /// Inputs accepted, as in §5.4: videos give MP4, MOV, GIF, MP3, M4A;
    /// audio files give MP3, M4A, WAV, FLAC.
    var acceptsVideo: Bool {
        switch self {
        case .mp4, .mov, .gif, .mp3, .m4a: true
        case .wav, .flac: false
        }
    }

    var acceptsAudio: Bool {
        switch self {
        case .mp3, .m4a, .wav, .flac: true
        case .mp4, .mov, .gif: false
        }
    }

    /// Whether `input` already has this format (§5.4: no X → X).
    func isSameFormat(as input: UTType) -> Bool {
        let types: [UTType] = switch self {
        case .mp4: [.mpeg4Movie]
        case .mov: [.quickTimeMovie]
        case .gif: [.gif]
        case .mp3: [.mp3]
        case .m4a: [.mpeg4Audio, FileTypes.m4a]
        case .wav: [.wav]
        case .flac: [FileTypes.flac]
        }
        return types.contains { input.conforms(to: $0) }
    }

    /// ffmpeg arguments between the input and the output file, chosen from
    /// what ffprobe found. `allowStreamCopy` rewraps streams that already
    /// have the target codec instead of re-encoding them (instant, lossless).
    func codecArguments(for probe: MediaProbe, allowStreamCopy: Bool, quality: OutputQuality = .standard) throws -> [String] {
        switch self {
        case .mp4, .mov:
            guard let video = probe.videoCodec else { throw OperationError.noVideo }
            var arguments = ["-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn"]
            arguments += allowStreamCopy && video == "h264"
                ? ["-c:v", "copy"]
                : ["-c:v", "h264_videotoolbox", "-q:v", quality.videoQuality, "-pix_fmt", "yuv420p"]
            arguments += allowStreamCopy && probe.audioCodec == "aac"
                ? ["-c:a", "copy"]
                : ["-c:a", "aac_at", "-b:a", "192k"]
            // Finder and QuickTime only preview H.264 tagged avc1.
            arguments += ["-tag:v", "avc1"]
            if self == .mp4 {
                arguments += ["-movflags", "+faststart"]
            }
            return arguments
        case .gif:
            guard probe.videoCodec != nil else { throw OperationError.noVideo }
            let filter = "fps=\(Self.gifFrameRate),scale='min(\(Self.gifMaxWidth),iw)':-1:flags=lanczos,"
                + "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
            return ["-map", "0:v:0", "-an", "-vf", filter, "-loop", "0"]
        case .mp3, .m4a, .wav, .flac:
            guard let audio = probe.audioCodec else { throw OperationError.noAudio }
            let codec: [String] = switch self {
            case .mp3: ["-c:a", "libmp3lame", "-b:a", "192k", "-id3v2_version", "3"]
            case .m4a: allowStreamCopy && audio == "aac" ? ["-c:a", "copy"] : ["-c:a", "aac_at", "-b:a", "256k"]
            case .wav: ["-c:a", "pcm_s16le"]
            default: ["-c:a", "flac"]
            }
            return ["-map", "0:a:0", "-vn"] + codec
        }
    }
}
