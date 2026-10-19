import AppKit

/// Detects a system-wide file drag (Finder, desktop…) and its end.
///
/// A drag session rewrites the shared drag pasteboard, so a change of its
/// `changeCount` since the last mouse-down means a drag has begun. The
/// pasteboard is only checked while the mouse is being dragged, and at most
/// every `checkInterval`, so the app costs nothing at rest (§7).
@MainActor
final class DragSessionMonitor {
    /// Called once per gesture when a drag carrying file URLs starts.
    var onFileDragStarted: (([URL]) -> Void)?
    /// Called on mouse-up after a file drag.
    var onFileDragEnded: (() -> Void)?

    /// Files of the drag in progress, nil when no file drag is active.
    private(set) var draggedFiles: [URL]?

    private static let checkInterval: TimeInterval = 0.03

    private let pasteboard = NSPasteboard(name: .drag)
    private var baselineChangeCount: Int
    private var lastCheck: TimeInterval = 0
    /// The current gesture turned out not to be a file drag (text, window move…).
    private var ignoringGesture = false
    private var monitors: [Any] = []

    init() {
        baselineChangeCount = pasteboard.changeCount
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            // Global monitor handlers are delivered on the main thread.
            MainActor.assumeIsolated { self.handle(event) }
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            baselineChangeCount = pasteboard.changeCount
            ignoringGesture = false
            draggedFiles = nil
        case .leftMouseDragged:
            guard draggedFiles == nil, !ignoringGesture,
                  event.timestamp - lastCheck >= Self.checkInterval else { return }
            lastCheck = event.timestamp
            checkForDragStart()
        case .leftMouseUp:
            baselineChangeCount = pasteboard.changeCount
            ignoringGesture = false
            if draggedFiles != nil {
                draggedFiles = nil
                onFileDragEnded?()
            }
        default:
            break
        }
    }

    private func checkForDragStart() {
        let count = pasteboard.changeCount
        guard count != baselineChangeCount else { return }
        baselineChangeCount = count

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if urls.isEmpty {
            ignoringGesture = true
            return
        }
        draggedFiles = urls
        onFileDragStarted?(urls)
    }
}
