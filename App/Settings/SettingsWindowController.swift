import AppKit
import SwiftUI

/// Owns the single Settings window. As an agent app (LSUIElement) we must
/// activate ourselves explicitly, otherwise the window opens behind others.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Réglages"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        // Reopening from another Space must bring the window here, not
        // switch the user back to the Space it was first shown on.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
