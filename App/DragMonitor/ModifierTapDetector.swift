import AppKit

/// A modifier key that can open a wheel when tapped during a drag.
enum TriggerKey: String, CaseIterable, Codable, Sendable {
    case shift, command, control, option

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .command: .command
        case .control: .control
        case .option: .option
        }
    }

    /// Symbol shown in the wheel title hint.
    var glyph: String {
        switch self {
        case .shift: "⇧"
        case .command: "⌘"
        case .control: "⌃"
        case .option: "⌥"
        }
    }

    /// Label in Settings.
    var name: String {
        switch self {
        case .shift: "⇧ Maj"
        case .command: "⌘ Commande"
        case .control: "⌃ Contrôle"
        case .option: "⌥ Option"
        }
    }

    static let allFlags: NSEvent.ModifierFlags = [.shift, .command, .control, .option]

    /// The key whose flag is the only one set, if any.
    static func only(in flags: NSEvent.ModifierFlags) -> TriggerKey? {
        allCases.first { $0.flag == flags }
    }
}

/// Recognises a "tap": one modifier pressed alone and released within
/// `maxTapDuration`, with no other key or modifier in between. Holding ⌘
/// (Finder's "move" override) is therefore never a tap.
///
/// Pure state machine fed with event data, so it can be unit tested.
struct ModifierTapDetector {
    static let maxTapDuration: TimeInterval = 0.4

    private var pending: (key: TriggerKey, downAt: TimeInterval)?
    private var previous: NSEvent.ModifierFlags = []

    /// Feeds a `flagsChanged` event. Returns the key when it completes a tap.
    mutating func flagsChanged(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) -> TriggerKey? {
        let current = flags.intersection(TriggerKey.allFlags)
        defer { previous = current }

        if previous.isEmpty, let key = TriggerKey.only(in: current) {
            pending = (key, time)
            return nil
        }
        if current.isEmpty, let tap = pending, previous == tap.key.flag {
            pending = nil
            return time - tap.downAt < Self.maxTapDuration ? tap.key : nil
        }
        // A second modifier joined in, or a partial release of a chord.
        pending = nil
        return nil
    }

    /// Any regular key pressed while a modifier is down cancels the tap.
    mutating func otherKeyPressed() {
        pending = nil
    }
}
