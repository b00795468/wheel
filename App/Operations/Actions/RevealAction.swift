import AppKit
import UniformTypeIdentifiers

/// "Afficher dans le Finder" (§5.4). The Finder window is the confirmation.
struct RevealAction: FileOperation {
    let id = "action.reveal"
    let kind = WheelMode.actions
    let title = "Afficher dans le Finder"
    let symbol = "folder"

    func accepts(_ types: [UTType]) -> Bool { !types.isEmpty }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(inputs) }
        return []
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? { nil }
}
