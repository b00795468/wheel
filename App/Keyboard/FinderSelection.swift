import Foundation

/// Files selected in the Finder, read through AppleScript (§5.3). The first
/// call makes macOS ask whether Pivot may control the Finder (Automation).
enum FinderSelection {
    enum Failure: Error, Equatable {
        case notAuthorized
        case unavailable(String)
    }

    /// AppleScript error "not authorized to send Apple events".
    private static let notAuthorizedError = -1743

    private static let source = """
    tell application "Finder"
        set selectedItems to selection as alias list
        set paths to {}
        repeat with selectedItem in selectedItems
            set end of paths to POSIX path of selectedItem
        end repeat
        return paths
    end tell
    """

    /// Runs off the main thread: the first call waits for the user's answer.
    static func current() async -> Result<[URL], Failure> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int
                    continuation.resume(returning: .failure(code == notAuthorizedError
                        ? .notAuthorized : .unavailable(error.description)))
                } else {
                    continuation.resume(returning: .success(parse(result)))
                }
            }
        }
    }

    /// POSIX paths from the script's list; folders end with "/".
    static func parse(_ descriptor: NSAppleEventDescriptor?) -> [URL] {
        guard let descriptor, descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0)?.stringValue }
            .map { URL(fileURLWithPath: $0, isDirectory: $0.hasSuffix("/")) }
    }
}
