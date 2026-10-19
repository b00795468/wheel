import AppKit
import Carbon.HIToolbox

/// The keyboard-mode shortcut (§5.3): a key with at least one of ⌘ ⌃ ⌥.
struct KeyCombo: Equatable, Codable, Sendable {
    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// ⌃⌥Espace (§5.3).
    static let standard = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.control, .option], keyLabel: "Espace")

    let keyCode: UInt16
    /// NSEvent.ModifierFlags raw value, limited to `allowedModifiers`.
    let modifierFlags: UInt
    /// What the key shows, captured when recorded ("Espace", "K"…).
    let keyLabel: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.allowedModifiers).rawValue
        self.keyLabel = keyLabel
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// ⌘, ⌃ or ⌥ is required so that plain typing never triggers it.
    var isValid: Bool { !modifiers.intersection([.command, .control, .option]).isEmpty }

    /// "⌃⌥Espace", modifiers in the macOS menu order ⌃ ⌥ ⇧ ⌘.
    var display: String {
        let glyphs: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    /// Label of a recorded key: a name for keys without a printable character.
    static func label(keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Espace"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: (characters ?? "").uppercased()
        }
    }
}
