import AppKit
import UniformTypeIdentifiers

/// "AirDrop" (§5.4) through the system sharing service, whose own window
/// is the confirmation. Pivot comes to the front so that window shows.
struct AirDropAction: FileOperation {
    let id = "action.airdrop"
    let kind = WheelMode.actions
    let title = "AirDrop"
    /// No public AirDrop symbol exists; the radio waves are its closest kin.
    let symbol = "dot.radiowaves.left.and.right"

    func accepts(_ types: [UTType]) -> Bool { !types.isEmpty }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try await MainActor.run {
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: inputs) else {
                throw OperationError.airDropUnavailable
            }
            NSApp.activate()
            service.perform(withItems: inputs)
        }
        return []
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? { nil }
}
