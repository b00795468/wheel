import UniformTypeIdentifiers
import XCTest

private struct FakeOperation: FileOperation {
    let id: String
    var group: OperationGroup? = nil
    var kind: WheelMode { .tools }
    var title: String { id }
    var symbol: String { "circle" }
    func accepts(_ types: [UTType]) -> Bool { !id.hasSuffix("never") }
    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] { [] }
}

final class RegistryGroupingTests: XCTestCase {
    private let resize = OperationGroup(id: "resize", title: "Redimensionner", symbol: "aspectratio")

    func testGroupedOperationsBecomeOneParentInRegistryOrder() {
        let registry = OperationRegistry(operations: [
            FakeOperation(id: "compress"),
            FakeOperation(id: "r1", group: resize),
            FakeOperation(id: "r2", group: resize),
            FakeOperation(id: "r3-never", group: resize),
            FakeOperation(id: "after"),
        ])

        let segments = registry.segments(for: [URL(fileURLWithPath: "/tmp/a.png")], kind: .tools)

        XCTAssertEqual(segments.map(\.id), ["compress", "resize", "after"])
        XCTAssertEqual(segments[1].title, "Redimensionner")
        XCTAssertEqual(segments[1].children.map(\.id), ["r1", "r2"])
        XCTAssertTrue(segments[0].children.isEmpty)
    }

    func testAGroupWithNoApplicableOperationDisappears() {
        let registry = OperationRegistry(operations: [FakeOperation(id: "x-never", group: resize)])
        XCTAssertEqual(registry.segments(for: [URL(fileURLWithPath: "/tmp/a.png")], kind: .tools), [])
    }
}
