import Foundation

/// Typed access to UserDefaults. Keys live here and nowhere else.
enum SettingsStore {
    private enum Key {
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
        static let outputDestination = "outputDestination"
        static let customOutputFolder = "customOutputFolder"
        static let stripsLocation = "stripsLocation"
        static let playsCompletionSound = "playsCompletionSound"
    }

    /// Stored values of `Key.outputDestination`.
    private enum DestinationValue {
        static let besideOriginal = "besideOriginal"
        static let custom = "custom"
    }

    private static var defaults: UserDefaults { .standard }

    static var hasCompletedFirstLaunch: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstLaunch) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstLaunch) }
    }

    // Read-only until the Settings window can change them (phase 6).

    static var outputDestination: OutputDestination {
        switch defaults.string(forKey: Key.outputDestination) {
        case DestinationValue.besideOriginal:
            return .besideOriginal
        case DestinationValue.custom:
            guard let path = defaults.string(forKey: Key.customOutputFolder) else { return .convertedFolder }
            return .custom(URL(fileURLWithPath: path, isDirectory: true))
        default:
            return .convertedFolder
        }
    }

    /// "Retirer les données de localisation", off by default (§5.5).
    static var stripsLocation: Bool {
        defaults.bool(forKey: Key.stripsLocation)
    }

    /// Discreet sound when a job finishes, on by default (§5.6).
    static var playsCompletionSound: Bool {
        defaults.object(forKey: Key.playsCompletionSound) as? Bool ?? true
    }
}
