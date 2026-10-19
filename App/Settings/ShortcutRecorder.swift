import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then type the new shortcut (⌘, ⌃ or ⌥ required); Escape cancels.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.combo = combo
        button.onRecord = { combo = $0 }
    }
}

final class RecorderButton: NSButton {
    var onRecord: ((KeyCombo) -> Void)?
    var combo = KeyCombo.standard {
        didSet { refreshTitle() }
    }
    private var isRecording = false {
        didSet { refreshTitle() }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    // Shortcuts with ⌘ arrive as key equivalents, the others as key downs.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                 keyLabel: KeyCombo.label(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
        guard candidate.isValid else { return }
        isRecording = false
        onRecord?(candidate)
    }

    private func refreshTitle() {
        title = isRecording ? "Tapez le raccourci…" : combo.display
    }
}
