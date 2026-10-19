import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppInfo.log.info("Launched \(AppInfo.name, privacy: .public) \(AppInfo.version, privacy: .public)")

        // The app has no Dock or menu bar icon: show Settings once so the
        // first launch is not silent. Onboarding replaces this in phase 6.
        if !SettingsStore.hasCompletedFirstLaunch {
            SettingsStore.hasCompletedFirstLaunch = true
            settingsWindow.show()
        }
    }

    /// Launching the app again (Finder, Spotlight, Launchpad) while it is
    /// already running is the only way to reach Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
