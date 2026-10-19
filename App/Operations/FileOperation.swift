import Foundation
import UniformTypeIdentifiers

/// "Qualité par défaut" (§5.7) for conversions. Compression keeps its own
/// fixed settings (§5.4).
enum OutputQuality: String, CaseIterable, Sendable {
    case standard, high

    var title: String {
        switch self {
        case .standard: "Standard"
        case .high: "Haute"
        }
    }

    /// JPEG, HEIC and AVIF encoder quality.
    var imageQuality: Double { self == .standard ? 0.9 : 0.97 }
    var webPQuality: Int { self == .standard ? 90 : 97 }
    /// h264_videotoolbox constant quality (1–100).
    var videoQuality: String { self == .standard ? "65" : "80" }
}

/// What an operation needs besides its inputs.
struct OperationContext: Sendable {
    let output: OutputLocator
    /// Drop GPS metadata from images (§5.5, off by default).
    let stripsLocation: Bool
    /// The embedded ffmpeg, nil when the app bundle lacks it.
    var ffmpeg: FFmpegRunner? = nil
    /// Encoder quality of conversions ("Qualité par défaut").
    var quality: OutputQuality = .standard
}

/// Operations shown together behind one segment that opens a sub-wheel.
struct OperationGroup: Equatable, Sendable {
    let id: String
    let title: String
    let symbol: String
}

/// One segment of a wheel. Adding a format means adding an operation to
/// `OperationRegistry.standard`, without touching the wheel (§4).
protocol FileOperation: Sendable {
    /// Stable identifier, e.g. "convert.png".
    var id: String { get }
    var kind: WheelMode { get }
    var title: String { get }
    var symbol: String { get }
    /// Long-running ffmpeg work, limited to a few concurrent jobs (§5.6).
    var usesMediaEngine: Bool { get }
    /// Pill text while the job runs, e.g. "Conversion en PNG".
    var progressTitle: String { get }
    /// Groups this operation with others behind a sub-wheel segment.
    var group: OperationGroup? { get }
    /// Text of the confirmation pill, nil for none (the action shows its own result).
    func completionMessage(inputs: [URL], outputs: [URL]) -> String?
    /// Whether the operation applies to files of all these types at once.
    func accepts(_ types: [UTType]) -> Bool
    /// Runs off the main thread. Returns the created files or folders.
    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL]
}

extension FileOperation {
    var segment: WheelSegment { WheelSegment(id: id, title: title, symbol: symbol) }
    var usesMediaEngine: Bool { false }
    var group: OperationGroup? { nil }

    /// Symbol for pills: label-only segments fall back to their wheel's symbol.
    var displaySymbol: String { symbol.isEmpty ? kind.symbol : symbol }

    var progressTitle: String {
        switch kind {
        case .convert: "Conversion en \(title)"
        case .tools, .actions: title
        }
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? {
        outputs.count == 1 ? "\(outputs[0].lastPathComponent) créé" : "\(outputs.count) fichiers créés"
    }
}

/// A failure the HUD can show as is: French, human, no jargon (§5.6).
/// `detail` carries the technical cause, for the log file only.
struct OperationError: LocalizedError, Equatable {
    let message: String
    var detail: String? = nil
    var errorDescription: String? { message }

    func withDetail(_ detail: String) -> OperationError {
        OperationError(message: message, detail: detail)
    }

    /// Two errors are the same when the user reads the same message.
    static func == (lhs: OperationError, rhs: OperationError) -> Bool {
        lhs.message == rhs.message
    }

    static let unreadableImage = OperationError(message: "Cette image semble corrompue ou illisible.")
    static let unreadablePDF = OperationError(message: "Ce PDF semble corrompu ou illisible.")
    static let lockedPDF = OperationError(message: "Ce PDF est protégé par un mot de passe.")
    static let writeFailed = OperationError(message: "Impossible d’enregistrer le fichier converti.")
    static let unreadableVideo = OperationError(message: "Ce fichier vidéo semble corrompu ou illisible.")
    static let unreadableAudio = OperationError(message: "Ce fichier audio semble corrompu ou illisible.")
    static let noAudio = OperationError(message: "Cette vidéo ne contient pas de son.")
    static let noVideo = OperationError(message: "Ce fichier ne contient pas d’image vidéo.")
    static let engineMissing = OperationError(message: "Le moteur audio et vidéo est introuvable. Réinstallez l’application.")
    static let alreadyCompressed = OperationError(message: "Ce fichier est déjà compressé au mieux.")
    static let airDropUnavailable = OperationError(message: "AirDrop n’est pas disponible. Vérifiez qu’il est activé.")

    static func alreadySmall(than limit: String) -> OperationError {
        OperationError(message: "Ce fichier fait déjà moins de \(limit).")
    }
}
