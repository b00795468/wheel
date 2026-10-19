import AppKit

/// Visual constants shared by the wheel and, later, the HUD.
enum Theme {
    /// Provisional accent (terracotta). Final choice pending (§6).
    static let accent = NSColor(srgbRed: 0xD9 / 255, green: 0x66 / 255, blue: 0x3F / 255, alpha: 1)

    static let appearDuration: TimeInterval = 0.14
    static let disappearDuration: TimeInterval = 0.10
    static let appearStartScale: CGFloat = 0.92
    static let hoverScale: CGFloat = 1.06
    static let hoverDuration: TimeInterval = 0.12
}
