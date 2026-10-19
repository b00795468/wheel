import AppKit
import SwiftUI

/// Owns the onboarding window, shown until it is completed once.
@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init(model: SettingsModel, onFinish: @escaping (Bool) -> Void) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Bienvenue dans \(AppInfo.name)"
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model, onFinish: onFinish))
        window.isReleasedWhenClosed = false
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
