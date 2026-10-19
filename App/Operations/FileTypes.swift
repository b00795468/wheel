import Foundation
import UniformTypeIdentifiers

/// File type detection from the URL alone. The wheel picks its segments
/// while the drag is still in flight, before the drop grants access to the
/// file, so nothing here may read it (reading triggers privacy prompts).
enum FileTypes {
    /// Declared by macOS 14+ (ImageIO reads and writes AVIF).
    static let avif = UTType("public.avif")!

    /// Image formats accepted as input (§5.4).
    static let imageInputs: [UTType] = [.jpeg, .png, .heic, .heif, .webP, .tiff, avif, .bmp]

    // Created from extensions, which always yields a type (declared or dynamic).
    static let m4a = UTType(filenameExtension: "m4a")!
    static let flac = UTType(filenameExtension: "flac")!
    private static let mkv = UTType(filenameExtension: "mkv")!
    private static let webm = UTType(filenameExtension: "webm")!
    private static let ogg = UTType(filenameExtension: "ogg")!

    /// Video and audio formats accepted as input (§5.4).
    static let videoInputs: [UTType] = [.mpeg4Movie, .quickTimeMovie, mkv, webm, .avi]
    static let audioInputs: [UTType] = [.mp3, .mpeg4Audio, m4a, .wav, flac, .aiff, ogg]

    static func type(of url: URL) -> UTType {
        if url.hasDirectoryPath { return .folder }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    static func isImage(_ type: UTType) -> Bool {
        imageInputs.contains { type.conforms(to: $0) }
    }

    static func isPDF(_ type: UTType) -> Bool {
        type.conforms(to: .pdf)
    }

    static func isVideo(_ type: UTType) -> Bool {
        videoInputs.contains { type.conforms(to: $0) }
    }

    static func isAudio(_ type: UTType) -> Bool {
        audioInputs.contains { type.conforms(to: $0) }
    }
}

extension URL {
    /// File name without its extension: "photo" for "photo.heic".
    var baseName: String { deletingPathExtension().lastPathComponent }
}
