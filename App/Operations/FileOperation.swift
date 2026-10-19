import Foundation
import UniformTypeIdentifiers

/// What an operation needs besides its inputs.
struct OperationContext: Sendable {
    let output: OutputLocator
    /// Drop GPS metadata from images (§5.5, off by default).
    let stripsLocation: Bool
}

/// One segment of a wheel. Adding a format means adding an operation to
/// `OperationRegistry.standard`, without touching the wheel (§4).
protocol FileOperation: Sendable {
    /// Stable identifier, e.g. "convert.png".
    var id: String { get }
    var kind: WheelMode { get }
    var title: String { get }
    var symbol: String { get }
    /// Whether the operation applies to files of all these types at once.
    func accepts(_ types: [UTType]) -> Bool
    /// Runs off the main thread. Returns the created files or folders.
    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL]
}

extension FileOperation {
    var segment: WheelSegment { WheelSegment(id: id, title: title, symbol: symbol) }
}

/// A failure the HUD can show as is: French, human, no jargon (§5.6).
struct OperationError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }

    static let unreadableImage = OperationError(message: "Cette image semble corrompue ou illisible.")
    static let unreadablePDF = OperationError(message: "Ce PDF semble corrompu ou illisible.")
    static let lockedPDF = OperationError(message: "Ce PDF est protégé par un mot de passe.")
    static let writeFailed = OperationError(message: "Impossible d'enregistrer le fichier converti.")
}
