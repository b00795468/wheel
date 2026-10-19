import AppKit

/// Pills stacked at the bottom-right of the screen reporting jobs (§5.6):
/// progress with a cancel button once a job runs over a second, then
/// "x créé" (click to reveal in Finder) or a human error message. Each
/// outcome is also spoken to VoiceOver, and a pill under the pointer stays.
@MainActor
final class HUDController {
    static let progressDelay: TimeInterval = 1
    static let successDuration: TimeInterval = 3
    static let noticeDuration: TimeInterval = 4
    static let failureDuration: TimeInterval = 5
    /// While the pointer rests on a pill, its removal waits this long again.
    private static let hoverGrace: TimeInterval = 1
    private static let margin: CGFloat = 16
    private static let spacing: CGFloat = 8

    private var visible: [HUDToast] = []

    func begin(title: String, symbol: String, onCancel: @escaping () -> Void) -> HUDToast {
        let toast = HUDToast(onCancel: onCancel)
        toast.showProgress(title: title, symbol: symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.progressDelay) { [weak self] in
            guard let self, toast.isRunning else { return }
            self.present(toast)
        }
        return toast
    }

    func succeed(_ toast: HUDToast, message: String, outputs: [URL], symbol: String) {
        toast.showSuccess(message: message, outputs: outputs, symbol: symbol)
        present(toast)
        Announcer.say(message)
        remove(toast, after: Self.successDuration)
    }

    func fail(_ toast: HUDToast, message: String) {
        toast.showFailure(message: message)
        present(toast)
        Announcer.say(message)
        remove(toast, after: Self.failureDuration)
    }

    func cancel(_ toast: HUDToast) {
        remove(toast, after: 0)
    }

    /// A short notice that is not about a job (keyboard mode, onboarding);
    /// with an `action`, clicking the pill runs it.
    func inform(_ message: String, symbol: String, action: (() -> Void)? = nil) {
        let toast = HUDToast(onCancel: {})
        toast.showSuccess(message: message, outputs: [], symbol: symbol, action: action)
        present(toast)
        Announcer.say(message)
        remove(toast, after: Self.noticeDuration)
    }

    private func present(_ toast: HUDToast) {
        let isNew = !visible.contains { $0 === toast }
        if isNew { visible.append(toast) }
        layout()
        if isNew { toast.appear() }
    }

    private func remove(_ toast: HUDToast, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.visible.contains(where: { $0 === toast }) else { return }
            if delay > 0, toast.isHovered {
                self.remove(toast, after: Self.hoverGrace)
                return
            }
            self.visible.removeAll { $0 === toast }
            toast.disappear()
            self.layout()
        }
    }

    /// Stacks the pills upwards from the bottom-right corner of the screen under the cursor.
    private func layout() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        var y = frame.minY + Self.margin
        for toast in visible {
            toast.panel.setFrameOrigin(CGPoint(x: frame.maxX - HUDToast.size.width - Self.margin, y: y))
            y += HUDToast.size.height + Self.spacing
        }
    }
}

/// One pill: a non-activating panel, so it never steals focus.
@MainActor
final class HUDToast {
    static let size = NSSize(width: 320, height: 64)
    /// Entrance: a short rise with a fade; Reduce Motion keeps the fade only.
    private static let appearDuration: TimeInterval = 0.18
    private static let disappearDuration: TimeInterval = 0.12
    private static let rise: CGFloat = 8

    let panel: NSPanel
    private let content: HUDToastView
    private let onCancel: () -> Void
    private var outputs: [URL] = []
    private var action: (() -> Void)?
    private(set) var isRunning = true

    var isHovered: Bool { content.isHovered }

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = Theme.hudAppearance
        content = HUDToastView(frame: NSRect(origin: .zero, size: Self.size))
        panel.contentView = content
        content.onClick = { [weak self] in self?.reveal() }
        content.onCancel = { [weak self] in self?.cancelTapped() }
    }

    func showProgress(title: String, symbol: String) {
        content.configure(icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil), tint: .labelColor,
                          text: "\(title)…", progress: 0, clickable: false)
    }

    func setProgress(_ fraction: Double) {
        guard isRunning else { return }
        content.setProgress(fraction)
    }

    /// Files: "x créé", where it went and a quiet "Afficher" cue. A notice
    /// with an `action` is clickable too.
    func showSuccess(message: String, outputs: [URL], symbol: String, action: (() -> Void)? = nil) {
        isRunning = false
        self.outputs = outputs
        self.action = action
        let icon = outputs.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if let folder = outputs.first?.deletingLastPathComponent().lastPathComponent {
            content.configure(icon: icon, tint: nil, text: message, progress: nil, clickable: true,
                              detail: "dans \(folder)", trailing: "Afficher", hint: "Afficher dans le Finder")
        } else {
            content.configure(icon: icon, tint: .labelColor, text: message, progress: nil, clickable: action != nil,
                              hint: action == nil ? nil : "Ouvrir les Réglages Système")
        }
    }

    /// The triangle carries the meaning; the colour stays neutral (one accent only, §6).
    func showFailure(message: String) {
        isRunning = false
        content.configure(icon: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil),
                          tint: .labelColor, text: message, progress: nil, clickable: false)
    }

    func appear() {
        let target = panel.frame.origin
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion {
            panel.setFrameOrigin(CGPoint(x: target.x, y: target.y - Self.rise))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrameOrigin(target)
            }
        }
    }

    func disappear() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.disappearDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { self.panel.orderOut(nil) }
        }
    }

    private func reveal() {
        if let action {
            action()
            return
        }
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    private func cancelTapped() {
        guard isRunning else { return }
        isRunning = false
        onCancel()
    }
}

@MainActor
private final class HUDToastView: NSView {
    private static let leading: CGFloat = 56
    private static let iconSide: CGFloat = 32
    private static let cancelSide: CGFloat = 24

    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isHovered = false
    private var isClickable = false

    private let material = NSVisualEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")
    private let bar = ProgressCapsule()
    private let cancelButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material.frame = bounds
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.masksToBounds = true
        addSubview(material)

        icon.frame = NSRect(x: 14, y: (bounds.height - Self.iconSide) / 2, width: Self.iconSide, height: Self.iconSide)
        icon.setAccessibilityElement(false)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.setAccessibilityElement(false)
        for secondary in [detailLabel, trailingLabel] {
            secondary.font = .systemFont(ofSize: 11)
            secondary.textColor = .secondaryLabelColor
            secondary.lineBreakMode = .byTruncatingMiddle
            secondary.setAccessibilityElement(false)
        }
        trailingLabel.alignment = .right
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Annuler")
        cancelButton.toolTip = "Annuler"
        cancelButton.isBordered = false
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.frame = NSRect(x: bounds.width - 36, y: (bounds.height - Self.cancelSide) / 2,
                                    width: Self.cancelSide, height: Self.cancelSide)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        [icon, label, detailLabel, trailingLabel, bar, cancelButton].forEach(addSubview)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `progress` nil hides the bar and the cancel button. A `detail` line
    /// (where the file went) keeps the message on one line; without it the
    /// message may use two. `trailing` is a quiet cue at the right edge.
    func configure(icon image: NSImage?, tint: NSColor?, text: String, progress: Double?, clickable: Bool,
                   detail: String? = nil, trailing: String? = nil, hint: String? = nil) {
        icon.image = image
        icon.contentTintColor = tint
        label.stringValue = text
        detailLabel.stringValue = detail ?? ""
        trailingLabel.stringValue = trailing ?? ""
        detailLabel.isHidden = detail == nil
        trailingLabel.isHidden = trailing == nil
        isClickable = clickable
        let running = progress != nil
        bar.isHidden = !running
        cancelButton.isHidden = !running
        bar.fraction = progress ?? 0
        let trailingWidth: CGFloat = trailing == nil ? 0 : 60
        let width = bounds.width - Self.leading - (running ? 48 : 16) - trailingWidth
        if running {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingMiddle
            label.frame = NSRect(x: Self.leading, y: 30, width: width, height: 16)
            bar.frame = NSRect(x: Self.leading, y: 20, width: width, height: 4)
        } else if detail != nil {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingMiddle
            label.frame = NSRect(x: Self.leading, y: 33, width: width, height: 16)
            detailLabel.frame = NSRect(x: Self.leading, y: 16, width: width, height: 14)
        } else {
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byWordWrapping
            let height = min(ceil(label.sizeThatFits(NSSize(width: width, height: 40)).height), 32)
            label.frame = NSRect(x: Self.leading, y: (bounds.height - height) / 2, width: width, height: height)
        }
        trailingLabel.frame = NSRect(x: bounds.width - 16 - 52, y: (bounds.height - 14) / 2, width: 52, height: 14)
        setAccessibilityLabel(detail.map { "\(text), \($0)" } ?? text)
        setAccessibilityRole(clickable ? .button : .staticText)
        setAccessibilityHelp(hint)
    }

    func setProgress(_ fraction: Double) {
        bar.fraction = fraction
    }

    // The panel belongs to an inactive app: cursor rects do not apply, a
    // tracking area with cursor updates does.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func cursorUpdate(with event: NSEvent) {
        (isClickable ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isClickable { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isClickable else { return false }
        onClick?()
        return true
    }

    @objc private func cancelPressed() {
        onCancel?()
    }
}

/// Thin progress bar in the accent colour (§6: the accent marks progress).
@MainActor
private final class ProgressCapsule: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        // A faint track: what must read is the terracotta fill against the pill.
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let width = bounds.width * min(max(fraction, 0), 1)
        guard width > 0 else { return }
        Theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(width, bounds.height), height: bounds.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

#if DEBUG
extension HUDToast {
    /// Offscreen render of one pill state, to check its layout without capture rights.
    static func debugSnapshot(state: String, to path: String) {
        let toast = HUDToast(onCancel: {})
        switch state {
        case "progress":
            toast.showProgress(title: "Conversion en PNG", symbol: "photo")
            toast.setProgress(0.42)
        case "failure":
            toast.showFailure(message: "Le moteur audio et vidéo est introuvable. Réinstallez l’application.")
        case "notice":
            toast.showSuccess(message: "Pivot est prêt\u{202F}: glissez un fichier, puis appuyez brièvement sur ⇧\u{00A0}Maj.",
                              outputs: [], symbol: "checkmark.circle")
        default:
            toast.showSuccess(message: "Vacances à la plage, été 2026.png créé", outputs: [URL(fileURLWithPath: "/etc/hosts")],
                              symbol: "photo")
        }
        let view = toast.content
        view.appearance = Theme.hudAppearance
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
