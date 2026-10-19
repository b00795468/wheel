import AppKit

/// Glues the gesture together: file drag in progress + modifier tap →
/// wheel at the cursor; another tap → switch wheel; Escape or mouse-up
/// outside the wheel → close without doing anything (§5.1).
@MainActor
final class GestureCoordinator {
    private static let escapeKeyCode: UInt16 = 53
    /// If the drag ends over the wheel but no drop arrives, close anyway.
    private static let dropGracePeriod: TimeInterval = 0.5

    private let dragMonitor = DragSessionMonitor()
    private let wheel = WheelController()
    private var tapDetector = ModifierTapDetector()
    private var keyMonitor: Any?

    func start() {
        dragMonitor.onFileDragStarted = { files in
            AppInfo.gestureLog.debug("File drag started: \(files.count) file(s)")
        }
        dragMonitor.onFileDragEnded = { [weak self] in self?.fileDragEnded() }
        dragMonitor.start()

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        }
    }

    private func handleKey(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard let key = tapDetector.flagsChanged(event.modifierFlags, at: event.timestamp) else { return }
            modifierTapped(key)
        case .keyDown:
            tapDetector.otherKeyPressed()
            if event.keyCode == Self.escapeKeyCode {
                wheel.dismiss(reason: "Escape")
            }
        default:
            break
        }
    }

    private func modifierTapped(_ key: TriggerKey) {
        guard let files = dragMonitor.draggedFiles, let mode = WheelMode.mode(for: key) else { return }
        if wheel.isVisible {
            wheel.switchMode(to: mode)
        } else {
            wheel.show(mode, files: files, at: NSEvent.mouseLocation)
        }
    }

    private func fileDragEnded() {
        guard wheel.isVisible else { return }
        guard wheel.isDragInside else {
            wheel.dismiss(reason: "drag ended outside the wheel")
            return
        }
        // The drop callback usually follows mouse-up; give it a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dropGracePeriod) { [weak self] in
            self?.wheel.dismiss(reason: "drag ended without drop")
        }
    }
}

#if DEBUG
extension GestureCoordinator {
    /// Shows the wheel without a drag, for checking its rendering:
    /// `open Pivot.app --args -debugWheel convert|tools|actions [-debugSlot N] [-debugSnapshot out.png]`.
    func showDebugWheelIfRequested() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: "debugWheel"),
              let mode = WheelMode.allCases.first(where: { "\($0)" == name }),
              let screen = NSScreen.main else { return }
        let files = [URL(fileURLWithPath: "/System/Library/Desktop Pictures"), URL(fileURLWithPath: "/etc/hosts")]
        wheel.show(mode, files: files, at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        if defaults.object(forKey: "debugSlot") != nil {
            wheel.debugHighlight(slot: defaults.integer(forKey: "debugSlot"))
        }
        if let path = defaults.string(forKey: "debugSnapshot") {
            wheel.debugSnapshot(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
