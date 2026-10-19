import AppKit

/// Shows, updates and hides the wheel panel, and turns drag positions over
/// it into highlights, paging and drops. The panel is built once at launch
/// so that showing it is just a move and fade (< 100 ms, §7).
@MainActor
final class WheelController {
    /// Lingering this long on "Plus…", "Retour" or a sub-wheel segment navigates (§5.2).
    private static let pagingDelay: TimeInterval = 0.5
    private static let titleGap: CGFloat = 2

    private let panel: WheelPanel
    private let dropTarget: WheelDropTarget
    private let wheelView = WheelView()
    private let titleView: WheelTitleView

    private var model: WheelModel?
    private var files: [URL] = []
    private var hoveredSlot: Int?
    private var navigationTimer: Timer?
    /// Bumped on every show/dismiss so a stale fade-out never hides a newer wheel.
    private var generation = 0

    /// Opened by the shortcut rather than a drag (§5.3).
    private var keyboardMode = false
    /// Hover announcements wait for the pointer to settle on a slot.
    private static let announcementDelay: Duration = .milliseconds(150)
    private var pendingAnnouncement: Task<Void, Never>?
    private var keyboardTapDetector = ModifierTapDetector()

    private enum KeyCode {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let escape: UInt16 = 53
    }

    private(set) var isVisible = false
    /// Whether the drag is currently over the panel.
    private(set) var isDragInside = false

    /// Segments offered by a wheel for the dragged files.
    var segmentsProvider: (WheelMode, [URL]) -> [WheelSegment] = { _, _ in [] }
    /// Called after files were dropped on a segment, with its id.
    var onDrop: ((String, [URL]) -> Void)?

    init() {
        let side = WheelView.side
        let size = NSSize(width: side, height: side + Self.titleGap + WheelTitleView.height)
        panel = WheelPanel(contentRect: NSRect(origin: .zero, size: size))
        dropTarget = WheelDropTarget(frame: NSRect(origin: .zero, size: size))
        dropTarget.wantsLayer = true
        dropTarget.wheelCenter = wheelView.center
        dropTarget.addSubview(wheelView)
        titleView = WheelTitleView(frame: NSRect(x: 0, y: side + Self.titleGap, width: side, height: WheelTitleView.height))
        dropTarget.addSubview(titleView)
        panel.contentView = dropTarget
        dropTarget.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKeyboard(event) ?? false }
        panel.onResignKey = { [weak self] in
            guard let self, self.keyboardMode else { return }
            self.dismiss(reason: "keyboard wheel lost focus")
        }
    }

    // MARK: Showing

    func show(_ mode: WheelMode, files: [URL], at screenPoint: CGPoint) {
        generation += 1
        self.files = files
        wheelView.setFiles(files)
        load(mode)
        panel.setFrameOrigin(origin(centeringWheelAt: screenPoint))

        let wasVisible = isVisible
        isVisible = true
        isDragInside = false
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        AppInfo.gestureLog.info("Wheel shown: \(mode.title, privacy: .public), \(files.count) file(s)")
        guard !wasVisible else { panel.alphaValue = 1; return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion, let layer = dropTarget.layer {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = CATransform3D.scale(Theme.appearStartScale, about: wheelView.center)
            animation.toValue = CATransform3DIdentity
            animation.duration = Theme.appearDuration
            // Slight overshoot for a soft spring.
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.25, 0.5, 1)
            layer.add(animation, forKey: "appear")
        }
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : Theme.appearDuration
            panel.animator().alphaValue = 1
        }
    }

    /// Switches the open wheel to another mode, keeping its position.
    func switchMode(to mode: WheelMode) {
        guard isVisible, mode != model?.mode else { return }
        load(mode)
        if keyboardMode { highlightFirstSlot() }
        AppInfo.gestureLog.info("Wheel switched to \(mode.title, privacy: .public)")
    }

    /// Keyboard mode: the wheel opens at the centre of the screen under the
    /// cursor, with the first slot highlighted.
    func showForKeyboard(_ mode: WheelMode, files: [URL]) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let center = screen.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? mouse
        keyboardMode = true
        keyboardTapDetector = ModifierTapDetector()
        show(mode, files: files, at: center)
        panel.acceptsKeyboard = true
        panel.makeKey()
        highlightFirstSlot()
        AppInfo.gestureLog.info("Keyboard wheel shown, panel is key: \(self.panel.isKeyWindow, privacy: .public)")
    }

    private func highlightFirstSlot() {
        setHoveredSlot(WheelModel.step(from: nil, count: model?.items.count ?? 0, forward: true))
    }

    private func handleKeyboard(_ event: NSEvent) -> Bool {
        guard keyboardMode, isVisible else { return false }
        if event.type == .flagsChanged {
            if let key = keyboardTapDetector.flagsChanged(event.modifierFlags, at: event.timestamp),
               let mode = SettingsStore.triggers.mode(for: key) {
                switchMode(to: mode)
            }
            return true
        }
        keyboardTapDetector.otherKeyPressed()
        let count = model?.items.count ?? 0
        switch event.keyCode {
        case KeyCode.right, KeyCode.down:
            setHoveredSlot(WheelModel.step(from: hoveredSlot, count: count, forward: true))
        case KeyCode.left, KeyCode.up:
            setHoveredSlot(WheelModel.step(from: hoveredSlot, count: count, forward: false))
        case KeyCode.returnKey, KeyCode.enter:
            activateHoveredSlot()
        case KeyCode.escape:
            dismiss(reason: "Escape (keyboard)")
        default:
            break
        }
        return true
    }

    /// Return on a slot: navigate like a long hover, or apply the segment.
    private func activateHoveredSlot() {
        guard let slot = hoveredSlot, let model, model.items.indices.contains(slot) else { return }
        if let navigation = navigation(for: model.items[slot]) {
            navigate(navigation)
        } else if case .segment(let segment) = model.items[slot] {
            deliver(segment)
        }
    }

    /// Applies a leaf segment to the files, for a drop or a Return.
    private func deliver(_ segment: WheelSegment) {
        let paths = files.map(\.path).joined(separator: ", ")
        AppInfo.gestureLog.notice("Apply \(segment.id, privacy: .public): \(paths, privacy: .public)")
        let chosen = files
        dismiss(reason: "applied \(segment.id)")
        onDrop?(segment.id, chosen)
    }

    func dismiss(reason: String) {
        guard isVisible else { return }
        isVisible = false
        isDragInside = false
        setHoveredSlot(nil)
        if keyboardMode {
            keyboardMode = false
            panel.acceptsKeyboard = false
        }
        generation += 1
        let dismissedGeneration = generation
        AppInfo.gestureLog.info("Wheel dismissed: \(reason, privacy: .public)")

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : Theme.disappearDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                guard self.generation == dismissedGeneration else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func load(_ mode: WheelMode) {
        model = WheelModel(mode: mode, segments: segmentsProvider(mode, files))
        reloadItems()
    }

    private func reloadItems() {
        setHoveredSlot(nil)
        guard let model else { return }
        titleView.setMode(model.mode, title: model.title, triggers: SettingsStore.triggers)
        let triggers = SettingsStore.triggers
        var emptyMessage = model.mode.emptyMessage
        if model.mode != .actions {
            // §5.2: when nothing applies, the Actions wheel stays one tap away.
            emptyMessage += "\n\(triggers.key(for: .actions).glyph)\u{00A0}\(WheelMode.actions.title) reste disponible"
        }
        wheelView.setItems(model.items, emptyMessage: emptyMessage)
        Announcer.say(model.items.isEmpty ? model.mode.emptyMessage : "\(model.title), \(model.items.count) choix")
    }

    /// Panel origin putting the wheel centre on `point`, kept inside the
    /// visible frame of the screen under the cursor.
    private func origin(centeringWheelAt point: CGPoint) -> CGPoint {
        let size = panel.frame.size
        var origin = CGPoint(x: point.x - wheelView.center.x, y: point.y - wheelView.center.y)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return origin
    }

    // MARK: Hover

    /// What lingering on a slot does.
    private enum Navigation {
        case nextPage, open(WheelSegment), back
    }

    private func navigation(for item: WheelItem) -> Navigation? {
        switch item {
        case .more: .nextPage
        case .back: .back
        case .segment(let segment): segment.children.isEmpty ? nil : .open(segment)
        }
    }

    fileprivate func setHoveredSlot(_ slot: Int?) {
        guard slot != hoveredSlot else { return }
        hoveredSlot = slot
        pendingAnnouncement?.cancel()
        wheelView.highlightedSlot = slot
        navigationTimer?.invalidate()
        navigationTimer = nil
        guard let slot, let model else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        let spoken = "\(model.items[slot].title), \(slot + 1) sur \(model.items.count)"
        pendingAnnouncement = Task { @MainActor in
            try? await Task.sleep(for: Self.announcementDelay)
            guard !Task.isCancelled else { return }
            Announcer.say(spoken)
        }
        if !keyboardMode, let navigation = navigation(for: model.items[slot]) {
            navigationTimer = Timer.scheduledTimer(withTimeInterval: Self.pagingDelay, repeats: false) { _ in
                MainActor.assumeIsolated { self.navigate(navigation) }
            }
        }
    }

    private func navigate(_ navigation: Navigation) {
        guard isVisible else { return }
        switch navigation {
        case .nextPage: model?.nextPage()
        case .open(let segment): model?.open(segment)
        case .back: model?.goBack()
        }
        reloadItems()
        if keyboardMode { highlightFirstSlot() }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func segment(at point: CGPoint) -> (slot: Int?, segment: WheelSegment?) {
        guard case .slot(let slot) = wheelView.geometry.hit(point), let model else { return (nil, nil) }
        // Only leaf segments take the drop; a parent opens its sub-wheel instead.
        if case .segment(let segment) = model.items[slot], segment.children.isEmpty { return (slot, segment) }
        return (slot, nil)
    }
}

extension WheelController: WheelDropTargetDelegate {
    func dropTarget(_ target: WheelDropTarget, dragMovedTo point: CGPoint?) -> NSDragOperation {
        guard isVisible, let point else {
            isDragInside = false
            setHoveredSlot(nil)
            return []
        }
        isDragInside = true
        let hit = segment(at: point)
        setHoveredSlot(hit.slot)
        // Only a leaf segment accepts the drop; the centre, "Plus…", "Retour" and parents refuse it.
        return hit.segment == nil ? [] : .copy
    }

    func dropTarget(_ target: WheelDropTarget, didDropAt point: CGPoint) -> Bool {
        guard isVisible, let segment = segment(at: point).segment else {
            dismiss(reason: "drop outside a segment")
            return false
        }
        deliver(segment)
        return true
    }
}

#if DEBUG
extension WheelController {
    func debugHighlight(slot: Int) {
        setHoveredSlot(slot)
    }

    /// Renders the panel content to a PNG. The behind-window material and
    /// layer transforms are not captured, only drawing and layout.
    func debugSnapshot(to url: URL) {
        dropTarget.appearance = Theme.hudAppearance
        dropTarget.layoutSubtreeIfNeeded()
        guard let rep = dropTarget.bitmapImageRepForCachingDisplay(in: dropTarget.bounds) else { return }
        dropTarget.cacheDisplay(in: dropTarget.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
