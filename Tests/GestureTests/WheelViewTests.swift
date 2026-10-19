import AppKit
import XCTest

@MainActor
final class WheelViewTests: XCTestCase {
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    /// Only the panel's root view handles drags. Any registered subview
    /// would swallow the drag and refuse it: a dead spot on the wheel.
    func testNoViewInsideTheWheelIsADropTarget() {
        let wheel = WheelView()
        wheel.setFiles([URL(fileURLWithPath: "/etc/hosts")])
        let segments = (0..<6).map { WheelSegment(id: "s\($0)", title: "S\($0)", symbol: "circle") }
        for items in [segments.map(WheelItem.segment) + [.more], []] {
            wheel.setItems(items, emptyMessage: WheelMode.convert.emptyMessage)
            for view in [wheel] + descendants(of: wheel) {
                XCTAssertEqual(view.registeredDraggedTypes, [], "\(type(of: view)) is a drop target")
            }
        }
    }
}
