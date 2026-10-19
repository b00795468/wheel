import ApplicationServices

/// Permission checks. Watching modifier keys and Escape in other apps
/// requires Accessibility. Live status and onboarding arrive in phase 6.
enum PermissionsManager {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt pointing to System Settings › Accessibility.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
