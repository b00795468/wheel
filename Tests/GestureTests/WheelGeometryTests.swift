import CoreGraphics
import XCTest

final class WheelGeometryTests: XCTestCase {
    private let middle = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2

    func testCentreAndOutsideZones() {
        let geometry = WheelGeometry(slotCount: 6)
        XCTAssertEqual(geometry.hit(.zero), .center)
        XCTAssertEqual(geometry.hit(CGPoint(x: WheelGeometry.innerRadius - 1, y: 0)), .center)
        XCTAssertEqual(geometry.hit(CGPoint(x: 0, y: WheelGeometry.outerRadius + 1)), .outside)
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
