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
    /// Accessibility is polled at this pace only while it is missing.
    private static let accessibilityPollInterval: TimeInterval = 2
    private var accessibilityTimer: Timer?
    private let registry = OperationRegistry.standard
    private let jobs = JobQueue()
    private let hotKeys = HotKeyCenter()
    private var hotKeyObserver: NSObjectProtocol?

    func start() {
        wheel.segmentsProvider = { [registry] mode, files in
            registry.segments(for: files, kind: mode)
        }
        wheel.onDrop = { [weak self] id, files in self?.runOperation(id, on: files) }
        dragMonitor.onFileDragStarted = { files in
            AppInfo.gestureLog.debug("File drag started: \(files.count) file(s)")
        }
        dragMonitor.onFileDragEnded = { [weak self] in self?.fileDragEnded() }
        dragMonitor.start()

        installKeyMonitor()
        watchAccessibilityUntilGranted()
        hotKeys.onPress = { [weak self] in self?.openFromKeyboard() }
        hotKeys.register(SettingsStore.hotKey)
        hotKeyObserver = NotificationCenter.default.addObserver(forName: SettingsStore.hotKeyDidChange, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.hotKeys.register(SettingsStore.hotKey) }
        }
    }

    private func installKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        }
    }

    /// Key monitors added before Accessibility is granted can stay deaf, so
    /// the monitor is installed again once it is (§5.7 "détection automatique").
    private func watchAccessibilityUntilGranted() {
        guard !PermissionsManager.isAccessibilityTrusted else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: Self.accessibilityPollInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard PermissionsManager.isAccessibilityTrusted else { return }
                timer.invalidate()
                self?.installKeyMonitor()
                AppInfo.log.info("Accessibility granted: key monitor installed again")
            }
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
        guard let files = dragMonitor.draggedFiles, let mode = SettingsStore.triggers.mode(for: key) else { return }
        if wheel.isVisible {
            wheel.switchMode(to: mode)
        } else {
            wheel.show(mode, files: files, at: NSEvent.mouseLocation)
        }
    }

    private func runOperation(_ id: String, on files: [URL]) {
        guard let operation = registry.operation(withID: id) else {
            AppInfo.jobLog.error("Unknown operation \(id, privacy: .public)")
            return
        }
        jobs.run(operation, inputs: files)
    }

    /// The shortcut (§5.3): opens the wheel on the Finder selection.
    private func openFromKeyboard() {
        guard !wheel.isVisible else { return }
        Task { [weak self] in
            let selection = await FinderSelection.current()
            guard let self else { return }
            switch selection {
            case .success(let files) where !files.isEmpty:
                self.wheel.showForKeyboard(.convert, files: files)
            case .success:
                self.jobs.inform("Sélectionnez des fichiers dans le Finder.", symbol: "cursorarrow.rays")
            case .failure(.notAuthorized):
                self.jobs.inform("Autorisez Pivot à piloter le Finder.", symbol: "lock")
                PermissionsManager.openAutomationSettings()
            case .failure(.unavailable(let detail)):
                TechnicalLog.record("Finder selection failed: \(detail)")
                self.jobs.inform("Impossible de lire la sélection du Finder.", symbol: "exclamationmark.triangle")
            }
        }
    }

    /// Called when the app quits, so no ffmpeg keeps running orphaned.
    func cancelAllJobs() {
        jobs.cancelAll()
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
    /// Development shortcuts, no drag needed:
    /// `open Pivot.app --args -debugWheel convert|tools|actions [-debugSlot N] [-debugSnapshot out.png]
    /// [-debugFiles '("/path/a", "/path/b")']` shows the wheel;
    /// `-debugRun convert.png -debugFiles '("/path/a")'` runs an operation as if dropped;
    /// `-debugKeyboard YES -debugFiles '("/path/a")'` opens the keyboard wheel without the shortcut.
    func performDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: "debugFiles") ?? ["/System/Library/Desktop Pictures/", "/etc/hosts"]
        let files = paths.map { URL(fileURLWithPath: $0) }

        if let id = defaults.string(forKey: "debugRun") {
            runOperation(id, on: files)
        }
        if defaults.bool(forKey: "debugKeyboard") {
            wheel.showForKeyboard(.convert, files: files)
            return
        }
        guard let name = defaults.string(forKey: "debugWheel"),
              let mode = WheelMode.allCases.first(where: { "\($0)" == name }),
              let screen = NSScreen.main else { return }
        wheel.show(mode, files: files, at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        if defaults.object(forKey: "debugSlot") != nil {
            wheel.debugHighlight(slot: defaults.integer(forKey: "debugSlot"))
        }
        if let path = defaults.string(forKey: "debugSnapshot") {
            // Leaves time for a hovered parent to open its sub-wheel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [wheel] in
                wheel.debugSnapshot(to: URL(fileURLWithPath: path))
            }
        }
    }
}
#endif
