import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var settingsWindow = SettingsWindowController()
    private let gestures = GestureCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppInfo.log.info("Launched \(AppInfo.name, privacy: .public) \(AppInfo.version, privacy: .public)")

        // Without Accessibility, modifier taps and Escape in other apps are
        // invisible to us. Proper onboarding replaces this prompt in phase 6.
        let trusted = PermissionsManager.isAccessibilityTrusted
        AppInfo.log.info("Accessibility trusted: \(trusted, privacy: .public)")
        if !trusted {
            PermissionsManager.requestAccessibility()
        }
        gestures.start()
        #if DEBUG
        gestures.performDebugLaunchArguments()
        #endif

        // The app has no Dock or menu bar icon: show Settings once so the
        // first launch is not silent. Onboarding replaces this in phase 6.
        if !SettingsStore.hasCompletedOnboarding {
            SettingsStore.hasCompletedOnboarding = true
            settingsWindow.show()
        }
    }

    /// Launching the app again (Finder, Spotlight, Launchpad) while it is
    /// already running is the only way to reach Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestures.cancelAllJobs()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
