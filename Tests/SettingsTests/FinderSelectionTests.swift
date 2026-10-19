import Foundation
import XCTest

final class FinderSelectionTests: XCTestCase {
    func testAListOfPOSIXPathsBecomesURLs() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "/Users/x/Été 🌞.jpg"), at: 1)
        list.insert(NSAppleEventDescriptor(string: "/Users/x/Vacances/"), at: 2)

        let urls = FinderSelection.parse(list)

        XCTAssertEqual(urls.map(\.path), ["/Users/x/Été 🌞.jpg", "/Users/x/Vacances"])
        XCTAssertTrue(urls[1].hasDirectoryPath, "a folder keeps its trailing slash, so it is typed as a folder")
    }

    func testEmptySelection() {
        XCTAssertEqual(FinderSelection.parse(NSAppleEventDescriptor.list()), [])
        XCTAssertEqual(FinderSelection.parse(nil), [])
    }
}
