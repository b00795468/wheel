import AppKit
import UniformTypeIdentifiers
import XCTest

final class ActionTests: XCTestCase {
    private let context = OperationContext(output: OutputLocator(destination: .besideOriginal), stripsLocation: false)

    func testCopyPathPutsPOSIXPathsOnePerLine() async throws {
        let name = "PivotTests-\(UUID().uuidString)"
        let action = CopyPathAction(pasteboardName: name)
        let inputs = [URL(fileURLWithPath: "/Users/x/Été 🌞.jpg"), URL(fileURLWithPath: "/Users/x/Vacances", isDirectory: true)]

        let outputs = try await action.run(inputs: inputs, context: context) { _ in }

        XCTAssertEqual(outputs, [])
        XCTAssertEqual(NSPasteboard(name: NSPasteboard.Name(name)).string(forType: .string),
                       "/Users/x/Été 🌞.jpg\n/Users/x/Vacances")
        XCTAssertEqual(action.completionMessage(inputs: inputs, outputs: outputs), "2 chemins copiés")
        XCTAssertEqual(action.completionMessage(inputs: [inputs[0]], outputs: []), "Chemin copié")
    }

    func testActionsAcceptAnythingIncludingFolders() {
        for action in [CopyPathAction(), RevealAction(), AirDropAction()] as [any FileOperation] {
            XCTAssertTrue(action.accepts([.folder]), action.id)
            XCTAssertTrue(action.accepts([.jpeg, .folder, .data]), action.id)
            XCTAssertFalse(action.accepts([]), action.id)
            XCTAssertEqual(action.kind, .actions)
        }
    }

    func testRevealAndAirDropNeedNoPill() {
        XCTAssertNil(RevealAction().completionMessage(inputs: [URL(fileURLWithPath: "/a")], outputs: []))
        XCTAssertNil(AirDropAction().completionMessage(inputs: [URL(fileURLWithPath: "/a")], outputs: []))
    }

    func testDefaultMessageNamesTheCreatedFile() {
        let operation = CompressOperation()
        XCTAssertEqual(operation.completionMessage(inputs: [], outputs: [URL(fileURLWithPath: "/o/a (compressé).jpg")]),
                       "a (compressé).jpg créé")
        XCTAssertEqual(operation.completionMessage(inputs: [], outputs: [URL(fileURLWithPath: "/o/a"), URL(fileURLWithPath: "/o/b")]),
                       "2 fichiers créés")
    }

    func testProgressTitlesNameTheWork() {
        XCTAssertEqual(ConvertToImageOperation(format: .png, acceptsPDF: true).progressTitle, "Conversion en PNG")
        XCTAssertEqual(CompressOperation().progressTitle, "Compression")
        XCTAssertEqual(ResizeOperation(preset: .long1920).progressTitle, "Redimensionnement à \(ResizePreset.long1920.title)")
        XCTAssertEqual(CopyPathAction().progressTitle, "Copier le chemin")
    }

    func testLabelOnlyFormatsFallBackToTheirWheelSymbolInPills() {
        let png = ConvertToImageOperation(format: .png, acceptsPDF: true)
        XCTAssertEqual(png.symbol, "")
        XCTAssertEqual(png.displaySymbol, WheelMode.convert.symbol)
        XCTAssertEqual(CopyPathAction().displaySymbol, "doc.on.clipboard")
        XCTAssertEqual(MediaConvertOperation(output: .mp4).symbol, "")
    }
}
