import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsModel()
    private lazy var settingsWindow = SettingsWindowController(model: settings)
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
        if let path = UserDefaults.standard.string(forKey: "debugSettingsSnapshot") {
            DebugSnapshot.render(SettingsView(model: settings), size: CGSize(width: 520, height: 660), to: path)
        }
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

#if DEBUG
/// Offscreen render of a SwiftUI view to a PNG, to check a window's layout
/// without screen capture rights.
@MainActor
enum DebugSnapshot {
    static func render<Content: View>(_ view: Content, size: CGSize, to path: String) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            window.close()
        }
    }
}
#endif
