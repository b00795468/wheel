import AppKit
import SwiftUI

/// Visual constants shared by the wheel, the HUD and the onboarding.
enum Theme {
    /// The single accent, #F0F1F1, chosen by Raphaël (his brother's
    /// favourite) instead of the SPEC's warm accent (§6). It is near white,
    /// so it lives only on dark surfaces: the wheel and the pills always use
    /// the dark appearance (`hudAppearance`), the onboarding draws its wheel
    /// on a dark stage.
    static let accent = NSColor(srgbRed: 0xF0 / 255, green: 0xF1 / 255, blue: 0xF1 / 255, alpha: 1)
    /// Text and icons on the accent: 14.9:1.
    static let onAccent = NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
    static let accentColor = Color(nsColor: accent)
    /// The wheel and pills stay dark in light mode too, like a HUD, so the
    /// near-white accent reads (12.5:1 on the dark material).
    static let hudAppearance = NSAppearance(named: .darkAqua)

    static let appearDuration: TimeInterval = 0.14
    static let disappearDuration: TimeInterval = 0.10
    static let appearStartScale: CGFloat = 0.92
    static let hoverScale: CGFloat = 1.06
    static let hoverDuration: TimeInterval = 0.12
    /// Crossfade when a wheel's items change (mode switch, page, sub-wheel).
    static let swapDuration: TimeInterval = 0.1
}
