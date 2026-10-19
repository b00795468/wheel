import XCTest

final class WheelModelTests: XCTestCase {
    private func segments(_ count: Int) -> [WheelSegment] {
        (0..<count).map { WheelSegment(id: "s\($0)", title: "S\($0)", symbol: "circle") }
    }

    private func ids(_ items: [WheelItem]) -> [String] {
        items.map { item in
            switch item {
            case .segment(let segment): segment.id
            case .more: "more"
            }
        }
    }

    func testUpToEightSegmentsFitOnOnePage() {
        let model = WheelModel(mode: .convert, segments: segments(8))
        XCTAssertEqual(model.pageCount, 1)
        XCTAssertEqual(model.items.count, 8)
        XCTAssertFalse(model.items.contains(.more))
    }

    func testMoreThanEightSegmentsArePagedWithAMoreSlot() {
        var model = WheelModel(mode: .convert, segments: segments(10))
        XCTAssertEqual(model.pageCount, 2)
        XCTAssertEqual(ids(model.items), ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "more"])
        model.nextPage()
        XCTAssertEqual(ids(model.items), ["s7", "s8", "s9", "more"])
        model.nextPage()
        XCTAssertEqual(model.page, 0, "paging wraps around")
    }

    func testEveryPageRespectsTheSlotLimit() {
        var model = WheelModel(mode: .tools, segments: segments(23))
        for _ in 0..<model.pageCount {
            XCTAssertLessThanOrEqual(model.items.count, WheelModel.maxItemsPerPage)
            model.nextPage()
        }
    }

    func testEmptyWheelHasNoItems() {
        let model = WheelModel(mode: .convert, segments: [])
        XCTAssertEqual(model.pageCount, 1)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testDefaultTriggersMapToDistinctModes() {
        XCTAssertEqual(WheelMode.mode(for: .shift), .convert)
        XCTAssertEqual(WheelMode.mode(for: .command), .tools)
        XCTAssertEqual(WheelMode.mode(for: .control), .actions)
        XCTAssertNil(WheelMode.mode(for: .option))
    }
}
