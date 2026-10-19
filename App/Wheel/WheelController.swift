import AppKit

/// Shows, updates and hides the wheel panel, and turns drag positions over
/// it into highlights, paging and drops. The panel is built once at launch
/// so that showing it is just a move and fade (< 100 ms, §7).
@MainActor
final class WheelController {
    /// Hovering "Plus…" this long turns the page (§5.2).
    private static let pagingDelay: TimeInterval = 0.5
    private static let titleGap: CGFloat = 2

    private let panel: WheelPanel
    private let dropTarget: WheelDropTarget
    private let wheelView = WheelView()
    private let titleView: WheelTitleView

    private var model: WheelModel?
    private var files: [URL] = []
    private var hoveredSlot: Int?
    private var pagingTimer: Timer?
    /// Bumped on every show/dismiss so a stale fade-out never hides a newer wheel.
    private var generation = 0

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
        AppInfo.gestureLog.info("Wheel switched to \(mode.title, privacy: .public)")
    }

    func dismiss(reason: String) {
        guard isVisible else { return }
        isVisible = false
        isDragInside = false
        setHoveredSlot(nil)
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
        titleView.setMode(mode)
        reloadItems()
    }

    private func reloadItems() {
        setHoveredSlot(nil)
        guard let model else { return }
        wheelView.setItems(model.items, emptyMessage: model.mode.emptyMessage)
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

    fileprivate func setHoveredSlot(_ slot: Int?) {
        guard slot != hoveredSlot else { return }
        hoveredSlot = slot
        wheelView.highlightedSlot = slot
        pagingTimer?.invalidate()
        pagingTimer = nil
        guard let slot, let model else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        if model.items[slot] == .more {
            pagingTimer = Timer.scheduledTimer(withTimeInterval: Self.pagingDelay, repeats: false) { _ in
                MainActor.assumeIsolated { self.turnPage() }
            }
        }
    }

    private func turnPage() {
        guard isVisible else { return }
        model?.nextPage()
        reloadItems()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func segment(at point: CGPoint) -> (slot: Int?, segment: WheelSegment?) {
        guard case .slot(let slot) = wheelView.geometry.hit(point), let model else { return (nil, nil) }
        if case .segment(let segment) = model.items[slot] { return (slot, segment) }
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
        // Only a real segment accepts the drop; the centre and "Plus…" refuse it.
        return hit.segment == nil ? [] : .copy
    }

    func dropTarget(_ target: WheelDropTarget, didDropAt point: CGPoint) -> Bool {
        guard isVisible, let segment = segment(at: point).segment else {
            dismiss(reason: "drop outside a segment")
            return false
        }
        let paths = files.map(\.path).joined(separator: ", ")
        AppInfo.gestureLog.notice("Drop on \(segment.id, privacy: .public): \(paths, privacy: .public)")
        let dropped = files
        dismiss(reason: "dropped on \(segment.id)")
        onDrop?(segment.id, dropped)
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
        dropTarget.appearance = NSApp.effectiveAppearance
        dropTarget.layoutSubtreeIfNeeded()
        guard let rep = dropTarget.bitmapImageRepForCachingDisplay(in: dropTarget.bounds) else { return }
        dropTarget.cacheDisplay(in: dropTarget.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
