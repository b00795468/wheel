import Foundation

/// Where converted files go (§5.5). Chosen in Settings from phase 6.
enum OutputDestination: Equatable, Sendable {
    case convertedFolder
    case besideOriginal
    case custom(URL)
}

/// Picks the output folder and a free name, and writes results atomically:
/// into a temporary file first, then moved under a name that does not
/// exist yet. Never overwrites, never touches the original (§5.5).
struct OutputLocator: Sendable {
    /// ~/Downloads/Convertis
    static let defaultConvertedFolder = URL.downloadsDirectory
        .appending(path: "Convertis", directoryHint: .isDirectory)

    let destination: OutputDestination
    var convertedFolder: URL = Self.defaultConvertedFolder

    /// Folder receiving the outputs of `input`, created if missing.
    func directory(for input: URL) throws -> URL {
        let directory: URL = switch destination {
        case .convertedFolder: convertedFolder
        case .besideOriginal: input.deletingLastPathComponent()
        case .custom(let folder): folder
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// First free name among "<base>.<ext>", "<base> 2.<ext>", "<base> 3.<ext>"…
    /// A nil extension names a folder.
    static func availableURL(in directory: URL, baseName: String, fileExtension: String?) -> URL {
        var number = 1
        while true {
            let name = number == 1 ? baseName : "\(baseName) \(number)"
            let url = directory.appending(path: fileExtension.map { "\(name).\($0)" } ?? name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }

    /// Lets `write` produce the file at a temporary URL on the same volume,
    /// then moves it to a free name and gives it the input's creation date.
    func commit(baseName: String, fileExtension: String, for input: URL,
                write: (URL) throws -> Void) throws -> URL {
        let staging = try Staging(locator: self, baseName: baseName, fileExtension: fileExtension, input: input)
        defer { staging.cleanUp() }
        try write(staging.temporary)
        return try staging.place()
    }

    /// `commit` for writers that are async, such as ffmpeg.
    func commitAsync(baseName: String, fileExtension: String, for input: URL,
                     write: (URL) async throws -> Void) async throws -> URL {
        let staging = try Staging(locator: self, baseName: baseName, fileExtension: fileExtension, input: input)
        defer { staging.cleanUp() }
        try await write(staging.temporary)
        return try staging.place()
    }

    /// A temporary file on the output volume, moved to a free name once written.
    private struct Staging {
        let directory: URL
        let folder: URL
        let temporary: URL
        let baseName: String
        let fileExtension: String
        let input: URL

        init(locator: OutputLocator, baseName: String, fileExtension: String, input: URL) throws {
            directory = try locator.directory(for: input)
            folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: directory, create: true)
            temporary = folder.appending(path: "\(baseName).\(fileExtension)")
            self.baseName = baseName
            self.fileExtension = fileExtension
            self.input = input
        }

        func place() throws -> URL {
            // Another job may take the same name between the check and the move.
            while true {
                let target = OutputLocator.availableURL(in: directory, baseName: baseName, fileExtension: fileExtension)
                do {
                    try FileManager.default.moveItem(at: temporary, to: target)
                    OutputLocator.copyCreationDate(from: input, to: target)
                    return target
                } catch CocoaError.fileWriteFileExists {
                    continue
                }
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Creates an empty folder under a free name, for multi-file results.
    func makeFolder(baseName: String, for input: URL) throws -> URL {
        let directory = try directory(for: input)
        while true {
            let folder = Self.availableURL(in: directory, baseName: baseName, fileExtension: nil)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                return folder
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
    }

    private static func copyCreationDate(from input: URL, to output: URL) {
        guard let date = try? input.resourceValues(forKeys: [.creationDateKey]).creationDate else { return }
        var values = URLResourceValues()
        values.creationDate = date
        var output = output
        try? output.setResourceValues(values)
    }
}
