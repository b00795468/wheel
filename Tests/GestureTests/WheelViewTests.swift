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
        for mode in WheelMode.allCases {
            wheel.setItems(PlaceholderSegments.segments(for: mode).map(WheelItem.segment) + [.more])
            for view in [wheel] + descendants(of: wheel) {
                XCTAssertEqual(view.registeredDraggedTypes, [], "\(type(of: view)) is a drop target")
            }
        }
    }
}
