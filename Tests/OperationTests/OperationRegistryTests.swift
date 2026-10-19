import XCTest

final class OperationRegistryTests: XCTestCase {
    private let registry = OperationRegistry.standard

    private func ids(_ paths: [String], _ kind: WheelMode = .convert) -> [String] {
        let urls = paths.map { URL(fileURLWithPath: "/tmp/\($0)", isDirectory: $0.hasSuffix("/")) }
        return registry.operations(for: urls, kind: kind).map(\.id)
    }

    func testAnImageOffersEveryOtherFormat() {
        XCTAssertEqual(ids(["a.png"]), ["convert.jpg", "convert.heic", "convert.tiff", "convert.pdf"])
        XCTAssertEqual(ids(["a.JPG"]), ["convert.png", "convert.heic", "convert.tiff", "convert.pdf"])
        XCTAssertFalse(ids(["a.heif"]).contains("convert.heic"))
    }

    func testWebPAVIFAndBMPAreAcceptedInputs() {
        for name in ["a.webp", "a.avif", "a.bmp"] {
            XCTAssertEqual(ids([name]), ["convert.jpg", "convert.png", "convert.heic", "convert.tiff", "convert.pdf"], name)
        }
    }

    func testPDFOffersPNGAndJPGOnly() {
        XCTAssertEqual(ids(["a.pdf"]), ["convert.jpg", "convert.png"])
    }

    func testSeveralFilesGetTheIntersection() {
        XCTAssertEqual(ids(["a.jpg", "b.png"]), ["convert.heic", "convert.tiff", "convert.pdf"])
        XCTAssertEqual(ids(["a.pdf", "b.png"]), ["convert.jpg"])
    }

    func testFoldersAndUnknownTypesGetNoConversion() {
        XCTAssertEqual(ids(["Vacances/"]), [])
        XCTAssertEqual(ids(["a.png", "Vacances/"]), [])
        XCTAssertEqual(ids(["notes.txt"]), [])
    }

    func testToolsAndActionsArriveInPhase5() {
        XCTAssertEqual(ids(["a.png"], .tools), [])
        XCTAssertEqual(ids(["a.png"], .actions), [])
    }

    func testIDsAreUniqueAndLookupWorks() {
        let all = registry.operations.map(\.id)
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertEqual(registry.operation(withID: "convert.png")?.title, "PNG")
        XCTAssertNil(registry.operation(withID: "nope"))
    }

    func testEveryWheelFitsOnOnePageForNow() {
        for mode in WheelMode.allCases {
            XCTAssertLessThanOrEqual(registry.operations.filter { $0.kind == mode }.count, WheelModel.maxItemsPerPage)
        }
    }
}
