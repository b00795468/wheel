import AppKit

/// Pills stacked at the bottom-right of the screen reporting jobs (§5.6):
/// progress with a cancel button once a job runs over a second, then
/// "x créé" (click to reveal in Finder) or a human error message.
@MainActor
final class HUDController {
    static let progressDelay: TimeInterval = 1
    static let successDuration: TimeInterval = 3
    static let failureDuration: TimeInterval = 5
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

    func succeed(_ toast: HUDToast, outputs: [URL]) {
        toast.showSuccess(outputs: outputs)
        present(toast)
        remove(toast, after: Self.successDuration)
    }

    func fail(_ toast: HUDToast, message: String) {
        toast.showFailure(message: message)
        present(toast)
        remove(toast, after: Self.failureDuration)
    }

    func cancel(_ toast: HUDToast) {
        remove(toast, after: 0)
    }

    private func present(_ toast: HUDToast) {
        if !visible.contains(where: { $0 === toast }) {
            visible.append(toast)
        }
        layout()
        toast.panel.orderFrontRegardless()
    }

    private func remove(_ toast: HUDToast, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.visible.removeAll { $0 === toast }
            toast.close()
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
    static let size = NSSize(width: 300, height: 56)

    let panel: NSPanel
    private let content: HUDToastView
    private let onCancel: () -> Void
    private var outputs: [URL] = []
    private(set) var isRunning = true

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
        content = HUDToastView(frame: NSRect(origin: .zero, size: Self.size))
        panel.contentView = content
        content.onClick = { [weak self] in self?.reveal() }
        content.onCancel = { [weak self] in self?.cancelTapped() }
    }

    func showProgress(title: String, symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        content.configure(icon: image, tint: .labelColor, text: "\(title)…", progress: 0)
    }

    func setProgress(_ fraction: Double) {
        guard isRunning else { return }
        content.setProgress(fraction)
    }

    func showSuccess(outputs: [URL]) {
        isRunning = false
        self.outputs = outputs
        let text = outputs.count == 1 ? "\(outputs[0].lastPathComponent) créé" : "\(outputs.count) fichiers créés"
        let icon = outputs.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
        content.configure(icon: icon, tint: nil, text: text, progress: nil)
    }

    func showFailure(message: String) {
        isRunning = false
        let icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: message)
        content.configure(icon: icon, tint: .systemOrange, text: message, progress: nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    private func reveal() {
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
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?

    private let material = NSVisualEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let cancelButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material.frame = bounds
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.masksToBounds = true
        addSubview(material)

        icon.frame = NSRect(x: 12, y: 12, width: 32, height: 32)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small
        bar.frame = NSRect(x: 54, y: 13, width: bounds.width - 54 - 44, height: 12)
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Annuler")
        cancelButton.isBordered = false
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.frame = NSRect(x: bounds.width - 36, y: 16, width: 24, height: 24)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        [icon, label, bar, cancelButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `progress` nil hides the bar and the cancel button.
    func configure(icon image: NSImage?, tint: NSColor?, text: String, progress: Double?) {
        icon.image = image
        icon.contentTintColor = tint
        label.stringValue = text
        let running = progress != nil
        bar.isHidden = !running
        cancelButton.isHidden = !running
        bar.doubleValue = progress ?? 0
        let textWidth = bounds.width - 54 - (running ? 44 : 14)
        label.frame = running
            ? NSRect(x: 54, y: 29, width: textWidth, height: 16)
            : NSRect(x: 54, y: 20, width: textWidth, height: 16)
    }

    func setProgress(_ fraction: Double) {
        bar.doubleValue = fraction
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    @objc private func cancelPressed() {
        onCancel?()
    }
}
