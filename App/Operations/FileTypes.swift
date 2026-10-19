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
}

extension URL {
    /// File name without its extension: "photo" for "photo.heic".
    var baseName: String { deletingPathExtension().lastPathComponent }
}
