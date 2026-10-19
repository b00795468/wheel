import Foundation

/// Typed access to UserDefaults. Keys live here and nowhere else.
enum SettingsStore {
    private enum Key {
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
    }

    private static var defaults: UserDefaults { .standard }

    static var hasCompletedFirstLaunch: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstLaunch) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstLaunch) }
    }
}
