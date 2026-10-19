import AppKit
import UniformTypeIdentifiers

/// "Copier le chemin" (§5.4): POSIX paths, one per line.
struct CopyPathAction: FileOperation {
    let id = "action.copyPath"
    let kind = WheelMode.actions
    let title = "Copier le chemin"
    let symbol = "doc.on.clipboard"
    /// The general pasteboard; a private one in tests.
    var pasteboardName = NSPasteboard.Name.general.rawValue

    func accepts(_ types: [UTType]) -> Bool { !types.isEmpty }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let text = inputs.map(\.path).joined(separator: "\n")
        await MainActor.run {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        return []
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? {
        inputs.count == 1 ? "Chemin copié" : "\(inputs.count) chemins copiés"
    }
}
