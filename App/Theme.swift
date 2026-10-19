import AppKit
import SwiftUI

/// Visual constants shared by the wheel, the HUD and the onboarding.
enum Theme {
    /// The single warm accent (§6), terracotta: progress, onboarding.
    static let accent = NSColor(srgbRed: 0xD9 / 255, green: 0x66 / 255, blue: 0x3F / 255, alpha: 1)
    /// Same hue one step deeper, behind the hovered segment's white label:
    /// about 4.9:1 where the lighter tone gives 3.55:1 (WCAG AA for 11 pt text).
    static let accentStrong = NSColor(srgbRed: 0xB8 / 255, green: 0x53 / 255, blue: 0x2F / 255, alpha: 1)
    static let accentColor = Color(nsColor: accent)

    static let appearDuration: TimeInterval = 0.14
    static let disappearDuration: TimeInterval = 0.10
    static let appearStartScale: CGFloat = 0.92
    static let hoverScale: CGFloat = 1.06
    static let hoverDuration: TimeInterval = 0.12
    /// Crossfade when a wheel's items change (mode switch, page, sub-wheel).
    static let swapDuration: TimeInterval = 0.1
}
