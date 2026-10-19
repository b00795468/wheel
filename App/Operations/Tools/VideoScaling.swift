import Foundation

/// ffmpeg scale filters that never enlarge and keep even sizes, which
/// H.264 and HEVC require.
enum VideoScaling {
    /// Longer side at most `longSide`, aspect ratio kept.
    static func fitting(longSide: Int) -> String {
        "scale='if(gte(iw,ih),min(\(longSide),trunc(iw/2)*2),-2)':'if(gte(iw,ih),-2,min(\(longSide),trunc(ih/2)*2))'"
    }

    static let half = "scale=trunc(iw/4)*2:trunc(ih/4)*2"
}
