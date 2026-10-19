import AppKit
import ApplicationServices

/// Permission states and shortcuts to the right System Settings panes (§5.7).
/// Only Accessibility is required: global key monitors and the Carbon
/// shortcut work without Input Monitoring (measured in phases 2 to 5).
enum PermissionsManager {
    enum Status {
        case granted, denied, notDetermined
    }

    private static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let automationPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    private static let finderBundleIdentifier = "com.apple.finder"

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt, which also adds Pivot to the Accessibility list.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Puts Pivot in the list, then opens the pane where it is switched on.
    static func grantAccessibility() {
        requestAccessibility()
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(accessibilityPane)
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(automationPane)
    }

    /// Whether Pivot may read the Finder selection, checked without asking.
    static func finderAutomationStatus() -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: finderBundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined
        }
    }
}
