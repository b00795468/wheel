import CoreGraphics
import XCTest

final class WheelGeometryTests: XCTestCase {
    private let middle = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2

    func testCentreAndOutsideZones() {
        let geometry = WheelGeometry(slotCount: 6)
        XCTAssertEqual(geometry.hit(.zero), .center)
        XCTAssertEqual(geometry.hit(CGPoint(x: WheelGeometry.innerRadius - 1, y: 0)), .center)
        XCTAssertEqual(geometry.hit(CGPoint(x: 0, y: WheelGeometry.hitRadius + 1)), .outside)
    }

    /// A hovered slot is drawn 6 % larger: its whole visible edge must still hit.
    func testGrownSlotEdgeIsNotADeadZone() {
        let geometry = WheelGeometry(slotCount: 6)
        XCTAssertGreaterThanOrEqual(WheelGeometry.hitRadius, WheelGeometry.outerRadius * 1.06)
        for radius in stride(from: WheelGeometry.outerRadius, through: WheelGeometry.outerRadius * 1.06, by: 1) {
            XCTAssertEqual(geometry.hit(geometry.point(inSlot: 2, radius: radius)), .slot(2), "radius \(radius)")
        }
    }

    /// Sweeping the whole ring finds a slot everywhere: no gaps between slots.
    func testRingHasNoAngularGaps() {
        for count in 1...WheelModel.maxItemsPerPage {
            let geometry = WheelGeometry(slotCount: count)
            for step in 0..<3600 {
                let angle = CGFloat(step) / 3600 * 2 * .pi
                for radius in [WheelGeometry.innerRadius + 0.5, middle, WheelGeometry.hitRadius - 0.5] {
                    let point = CGPoint(x: radius * sin(angle), y: radius * cos(angle))
                    guard case .slot = geometry.hit(point) else {
                        return XCTFail("no slot at angle \(angle), radius \(radius), \(count) slots")
                    }
                }
            }
        }
    }

    func testFourSlotsFollowTheCompassClockwise() {
        let geometry = WheelGeometry(slotCount: 4)
        XCTAssertEqual(geometry.hit(CGPoint(x: 0, y: middle)), .slot(0))    // top
        XCTAssertEqual(geometry.hit(CGPoint(x: middle, y: 0)), .slot(1))    // right
        XCTAssertEqual(geometry.hit(CGPoint(x: 0, y: -middle)), .slot(2))   // bottom
        XCTAssertEqual(geometry.hit(CGPoint(x: -middle, y: 0)), .slot(3))   // left
    }

    func testSlotZeroStraddlesTwelveOClock() {
        let geometry = WheelGeometry(slotCount: 4)
        XCTAssertEqual(geometry.hit(CGPoint(x: -10, y: middle)), .slot(0))
        XCTAssertEqual(geometry.hit(CGPoint(x: 10, y: middle)), .slot(0))
    }

    func testEverySlotCentreHitsItsOwnSlot() {
        for count in 1...WheelModel.maxItemsPerPage {
            let geometry = WheelGeometry(slotCount: count)
            for slot in 0..<count {
                XCTAssertEqual(geometry.hit(geometry.point(inSlot: slot, radius: middle)), .slot(slot),
                               "slot \(slot) of \(count)")
            }
        }
    }

    func testNoSlotsMeansNoSegmentHit() {
        XCTAssertEqual(WheelGeometry(slotCount: 0).hit(CGPoint(x: 0, y: middle)), .center)
    }
}
