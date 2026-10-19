import AppKit

/// Transparent, non-activating panel floating above every app and the Dock.
/// It only becomes key in keyboard mode, so the frontmost app keeps focus (§5.2).
final class WheelPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        appearance = Theme.hudAppearance
    }

    /// Keyboard mode (§5.3): the panel takes key events without activating
    /// Pivot, as a non-activating panel may. Never during a drag.
    var acceptsKeyboard = false
    /// Returns true when it handled the key or modifier event.
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboard }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        if keyHandler?(event) != true { super.flagsChanged(with: event) }
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override var canBecomeMain: Bool { false }
}
