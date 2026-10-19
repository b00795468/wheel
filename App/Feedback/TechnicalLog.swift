import Foundation

/// Technical failure details, in ~/Library/Logs/<App>/<App>.log (§5.6).
/// The HUD only ever shows the human message.
enum TechnicalLog {
    static var fileURL: URL {
        URL.libraryDirectory.appending(path: "Logs/\(AppInfo.name)/\(AppInfo.name).log")
    }

    static func record(_ message: String) {
        AppInfo.jobLog.error("\(message, privacy: .public)")
        let url = fileURL
        let line = "\(Date().ISO8601Format()) \(message)\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            AppInfo.jobLog.error("Cannot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
