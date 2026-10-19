import AppKit

@MainActor
protocol WheelDropTargetDelegate: AnyObject {
    /// The drag moved to `point` (wheel-centred, y up), or left the wheel
    /// when nil. Returns the operation to show to the drag source.
    func dropTarget(_ target: WheelDropTarget, dragMovedTo point: CGPoint?) -> NSDragOperation
    /// The files were dropped at `point`. Returns whether the drop was accepted.
    func dropTarget(_ target: WheelDropTarget, didDropAt point: CGPoint) -> Bool
}

/// Root view of the wheel panel: receives the system drag and converts
/// its location into wheel coordinates. Only `.copy` is ever offered, so
/// the drag source never moves or deletes the original (§5.1).
@MainActor
final class WheelDropTarget: NSView {
    weak var delegate: WheelDropTargetDelegate?

    /// Wheel centre, in this view's coordinates.
    var wheelCenter: CGPoint = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func wheelPoint(_ sender: NSDraggingInfo) -> CGPoint {
        let local = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: local.x - wheelCenter.x, y: local.y - wheelCenter.y)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.dropTarget(self, dragMovedTo: wheelPoint(sender)) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.dropTarget(self, dragMovedTo: wheelPoint(sender)) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        _ = delegate?.dropTarget(self, dragMovedTo: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        delegate?.dropTarget(self, didDropAt: wheelPoint(sender)) ?? false
    }
}
