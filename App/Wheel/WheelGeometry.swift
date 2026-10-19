import CoreGraphics
import Foundation

/// Ring layout and hit-testing, in points relative to the wheel centre
/// (y up). Slot 0 is centred at the top; slots go clockwise.
struct WheelGeometry {
    static let outerRadius: CGFloat = 140   // ~280 pt diameter (§5.2)
    static let innerRadius: CGFloat = 54    // neutral centre / cancel zone
    /// Slots accept the drag up to here, beyond the drawn ring, so the edge
    /// of a hovered slot (grown by 6 %, ~148 pt) is never a dead zone.
    static let hitRadius: CGFloat = 152

    enum Hit: Equatable {
        case center
        case slot(Int)
        case outside
    }

    let slotCount: Int

    var slotAngle: CGFloat { slotCount > 0 ? 2 * .pi / CGFloat(slotCount) : 0 }

    func hit(_ point: CGPoint) -> Hit {
        let distance = hypot(point.x, point.y)
        if distance > Self.hitRadius { return .outside }
        if distance < Self.innerRadius || slotCount == 0 { return .center }
        // Clockwise angle from the top, shifted by half a slot so that
        // slot 0 spans [-half, +half] around 12 o'clock.
        var angle = atan2(point.x, point.y) + slotAngle / 2
        if angle < 0 { angle += 2 * .pi }
        return .slot(Int(angle / slotAngle) % slotCount)
    }

    /// Clockwise angle from the top of the slot's middle, in radians.
    func midAngle(ofSlot index: Int) -> CGFloat {
        CGFloat(index) * slotAngle
    }

    /// Point at `radius` along the middle of a slot.
    func point(inSlot index: Int, radius: CGFloat) -> CGPoint {
        let angle = midAngle(ofSlot: index)
        return CGPoint(x: radius * sin(angle), y: radius * cos(angle))
    }
}
