import Foundation

/// Runs the embedded ffmpeg / ffprobe. Completed in the next task.
struct FFmpegRunner: Sendable {
    let ffmpeg: URL
    let ffprobe: URL
}
