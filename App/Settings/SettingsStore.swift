import Foundation

/// Typed access to UserDefaults. Keys live here and nowhere else.
enum SettingsStore {
    private enum Key {
        /// Name kept from phase 1, when it only marked the first launch.
        static let hasCompletedOnboarding = "hasCompletedFirstLaunch"
        static let outputDestination = "outputDestination"
        static let customOutputFolder = "customOutputFolder"
        static let stripsLocation = "stripsLocation"
        static let playsCompletionSound = "playsCompletionSound"
        static let outputQuality = "outputQuality"
        static let triggers = "triggers"
        static let hotKey = "hotKey"
    }

    /// Stored values of `Key.outputDestination`.
    private enum DestinationValue {
        static let converted = "converted"
        static let besideOriginal = "besideOriginal"
        static let custom = "custom"
    }

    /// Posted when the keyboard shortcut changes, so it gets registered again.
    static let hotKeyDidChange = Notification.Name("PivotHotKeyDidChange")

    /// A private suite in tests.
    static var defaults: UserDefaults = .standard

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    static var outputDestination: OutputDestination {
        get {
            switch defaults.string(forKey: Key.outputDestination) {
            case DestinationValue.besideOriginal:
                return .besideOriginal
            case DestinationValue.custom:
                return customOutputFolder.map(OutputDestination.custom) ?? .convertedFolder
            default:
                return .convertedFolder
            }
        }
        set {
            switch newValue {
            case .convertedFolder:
                defaults.set(DestinationValue.converted, forKey: Key.outputDestination)
            case .besideOriginal:
                defaults.set(DestinationValue.besideOriginal, forKey: Key.outputDestination)
            case .custom(let folder):
                defaults.set(DestinationValue.custom, forKey: Key.outputDestination)
                defaults.set(folder.path, forKey: Key.customOutputFolder)
            }
        }
    }

    /// Last folder picked, kept while another destination is selected.
    static var customOutputFolder: URL? {
        defaults.string(forKey: Key.customOutputFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// "Retirer les données de localisation", off by default (§5.5).
    static var stripsLocation: Bool {
        get { defaults.bool(forKey: Key.stripsLocation) }
        set { defaults.set(newValue, forKey: Key.stripsLocation) }
    }

    /// Discreet sound when a job finishes, on by default (§5.6).
    static var playsCompletionSound: Bool {
        // bool(forKey:) also understands "NO"/"0" strings (launch arguments).
        get { defaults.object(forKey: Key.playsCompletionSound) == nil ? true : defaults.bool(forKey: Key.playsCompletionSound) }
        set { defaults.set(newValue, forKey: Key.playsCompletionSound) }
    }

    static var outputQuality: OutputQuality {
        get { defaults.string(forKey: Key.outputQuality).flatMap(OutputQuality.init) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: Key.outputQuality) }
    }

    static var triggers: TriggerMapping {
        get { decode(TriggerMapping.self, forKey: Key.triggers) ?? .standard }
        set { encode(newValue, forKey: Key.triggers) }
    }

    static var hotKey: KeyCombo {
        get { decode(KeyCombo.self, forKey: Key.hotKey) ?? .standard }
        set {
            encode(newValue, forKey: Key.hotKey)
            NotificationCenter.default.post(name: hotKeyDidChange, object: nil)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
