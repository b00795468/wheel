import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsModel()
    private lazy var settingsWindow = SettingsWindowController(model: settings)
    private lazy var onboardingWindow = OnboardingWindowController(model: settings) { [weak self] launchAtLogin in
        self?.finishOnboarding(launchAtLogin: launchAtLogin)
    }
    private let gestures = GestureCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppInfo.log.info("Launched \(AppInfo.name, privacy: .public) \(AppInfo.version, privacy: .public)")

        let trusted = PermissionsManager.isAccessibilityTrusted
        AppInfo.log.info("Accessibility trusted: \(trusted, privacy: .public)")
        gestures.start()
        #if DEBUG
        gestures.performDebugLaunchArguments()
        if let path = UserDefaults.standard.string(forKey: "debugSettingsSnapshot") {
            DebugSnapshot.render(SettingsView(model: settings), size: CGSize(width: 520, height: 660), to: path)
        }
        if let path = UserDefaults.standard.string(forKey: "debugHUDSnapshot") {
            HUDToast.debugSnapshot(state: UserDefaults.standard.string(forKey: "debugHUDState") ?? "success", to: path)
        }
        if let path = UserDefaults.standard.string(forKey: "debugOnboardingSnapshot") {
            let page = UserDefaults.standard.integer(forKey: "debugOnboardingPage")
            DebugSnapshot.render(OnboardingView(model: settings, page: page) { _ in },
                                 size: CGSize(width: 560, height: 470), to: path)
        }
        #endif

        // The app has no Dock or menu bar icon: the first launch shows the
        // onboarding (§5.7), later launches stay silent unless a permission is missing.
        if !SettingsStore.hasCompletedOnboarding {
            onboardingWindow.show()
        } else if !trusted {
            PermissionsManager.requestAccessibility()
        }
    }

    private func finishOnboarding(launchAtLogin: Bool) {
        SettingsStore.hasCompletedOnboarding = true
        LoginItem.setEnabled(launchAtLogin)
        settings.refreshPermissions()
        onboardingWindow.close()
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
