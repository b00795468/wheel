import AppKit

/// Spoken feedback for VoiceOver: the wheel and the pills never take focus,
/// so what happens on them is announced instead (§7, accessibility).
@MainActor
enum Announcer {
    static func say(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
