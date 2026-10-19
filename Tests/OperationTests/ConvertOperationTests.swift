import PDFKit
import XCTest

final class ConvertOperationTests: XCTestCase {
    func testConvertRunsOnEveryInputAndReportsProgress() async throws {
        let dir = try Fixtures.directory(for: self)
        let png = try Fixtures.writeImage("a.png", in: dir, type: .png)
        let pdf = try Fixtures.writePDF("doc.pdf", in: dir, pages: Array(repeating: CGSize(width: 100, height: 100), count: 3))
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        let progress = ProgressRecorder()
        let context = OperationContext(output: OutputLocator(destination: .custom(out)), stripsLocation: false)

        let outputs = try await ConvertToImageOperation(format: .jpeg, acceptsPDF: true)
            .run(inputs: [png, pdf], context: context) { progress.record($0) }

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["a.jpg", "doc"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputs[1].path).count, 3)
        XCTAssertEqual(progress.last, 1)
    }

    func testImagesToPDFMergesInDragOrder() async throws {
        let dir = try Fixtures.directory(for: self)
        let first = try Fixtures.writeImage("z.png", in: dir, type: .png, width: 40, height: 20)
        let second = try Fixtures.writeImage("a.jpg", in: dir, type: .jpeg, width: 20, height: 40)
        let context = OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))),
                                       stripsLocation: false)

        let outputs = try await ImagesToPDFOperation().run(inputs: [first, second], context: context) { _ in }

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["z.pdf"])
        let document = try XCTUnwrap(PDFDocument(url: outputs[0]))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).width, 40)
    }

    func testCancelledJobThrowsAndWritesNothing() async throws {
        let dir = try Fixtures.directory(for: self)
        let png = try Fixtures.writeImage("a.png", in: dir, type: .png)
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        let context = OperationContext(output: OutputLocator(destination: .custom(out)), stripsLocation: false)

        let task = Task {
            try await ConvertToImageOperation(format: .jpeg, acceptsPDF: true).run(inputs: [png], context: context) { _ in }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appending(path: "a.jpg").path))
    }
}
