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
            case .back: "back"
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

    private func parent(children count: Int) -> WheelSegment {
        WheelSegment(id: "group", title: "Redimensionner", symbol: "aspectratio", children: segments(count))
    }

    func testOpeningAGroupShowsItsChildrenAndBack() {
        var model = WheelModel(mode: .tools, segments: [WheelSegment(id: "c", title: "C", symbol: "circle"), parent(children: 4)])
        XCTAssertEqual(model.title, "Outils")

        model.open(parent(children: 4))

        XCTAssertEqual(model.title, "Redimensionner")
        XCTAssertEqual(ids(model.items), ["s0", "s1", "s2", "s3", "back"])
        model.goBack()
        XCTAssertEqual(ids(model.items), ["c", "group"])
        XCTAssertEqual(model.title, "Outils")
    }

    func testALeafSegmentDoesNotOpen() {
        var model = WheelModel(mode: .tools, segments: segments(2))
        model.open(segments(1)[0])
        XCTAssertNil(model.parent)
    }

    func testABigSubWheelPagesAndKeepsBack() {
        var model = WheelModel(mode: .tools, segments: [parent(children: 10)])
        model.open(parent(children: 10))

        XCTAssertEqual(ids(model.items), ["s0", "s1", "s2", "s3", "s4", "s5", "more", "back"])
        model.nextPage()
        XCTAssertEqual(ids(model.items), ["s6", "s7", "s8", "s9", "more", "back"])
    }

    func testArrowStepsWrapAround() {
        XCTAssertEqual(WheelModel.step(from: nil, count: 4, forward: true), 0)
        XCTAssertEqual(WheelModel.step(from: nil, count: 4, forward: false), 3)
        XCTAssertEqual(WheelModel.step(from: 3, count: 4, forward: true), 0)
        XCTAssertEqual(WheelModel.step(from: 0, count: 4, forward: false), 3)
        XCTAssertEqual(WheelModel.step(from: 1, count: 4, forward: true), 2)
        XCTAssertNil(WheelModel.step(from: nil, count: 0, forward: true))
    }
}
