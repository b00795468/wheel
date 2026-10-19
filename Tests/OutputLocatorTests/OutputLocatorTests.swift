import XCTest

final class OutputLocatorTests: XCTestCase {
    private func write(_ text: String) -> (URL) throws -> Void {
        { url in try Data(text.utf8).write(to: url) }
    }

    private func contents(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func testFreeNamesFollowFinderStyleNumbering() throws {
        let dir = try Fixtures.directory(for: self)
        XCTAssertEqual(OutputLocator.availableURL(in: dir, baseName: "photo", fileExtension: "png").lastPathComponent, "photo.png")
        try Data().write(to: dir.appending(path: "photo.png"))
        XCTAssertEqual(OutputLocator.availableURL(in: dir, baseName: "photo", fileExtension: "png").lastPathComponent, "photo 2.png")
        try Data().write(to: dir.appending(path: "photo 2.png"))
        XCTAssertEqual(OutputLocator.availableURL(in: dir, baseName: "photo", fileExtension: "png").lastPathComponent, "photo 3.png")
        XCTAssertEqual(OutputLocator.availableURL(in: dir, baseName: "photo", fileExtension: nil).lastPathComponent, "photo")
    }

    func testCommitNeverOverwritesAnExistingFile() throws {
        let dir = try Fixtures.directory(for: self)
        let existing = dir.appending(path: "photo.png")
        try Data("original".utf8).write(to: existing)
        let locator = OutputLocator(destination: .custom(dir))

        let output = try locator.commit(baseName: "photo", fileExtension: "png", for: existing, write: write("new"))

        XCTAssertEqual(output.lastPathComponent, "photo 2.png")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "new")
    }

    func testDefaultFolderIsCreatedWhenMissing() throws {
        let dir = try Fixtures.directory(for: self)
        let folder = dir.appending(path: "a/b/Convertis", directoryHint: .isDirectory)
        let locator = OutputLocator(destination: .convertedFolder, convertedFolder: folder)

        let output = try locator.commit(baseName: "x", fileExtension: "png", for: dir.appending(path: "x.jpg"), write: write("1"))

        XCTAssertEqual(output.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
    }

    func testDefaultFolderIsDownloadsConvertis() {
        XCTAssertEqual(OutputLocator.defaultConvertedFolder.lastPathComponent, "Convertis")
        XCTAssertEqual(OutputLocator.defaultConvertedFolder.deletingLastPathComponent().standardizedFileURL,
                       URL.downloadsDirectory.standardizedFileURL)
    }

    func testBesideOriginalAndCustomFolder() throws {
        let dir = try Fixtures.directory(for: self)
        let source = dir.appending(path: "src", directoryHint: .isDirectory)
        let custom = dir.appending(path: "custom", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let input = source.appending(path: "x.jpg")

        let beside = try OutputLocator(destination: .besideOriginal)
            .commit(baseName: "x", fileExtension: "png", for: input, write: write("1"))
        let elsewhere = try OutputLocator(destination: .custom(custom))
            .commit(baseName: "x", fileExtension: "png", for: input, write: write("2"))

        XCTAssertEqual(beside.path, source.appending(path: "x.png").path)
        XCTAssertEqual(elsewhere.path, custom.appending(path: "x.png").path)
    }

    func testNamesWithAccentsSpacesAndEmoji() throws {
        let dir = try Fixtures.directory(for: self)
        let locator = OutputLocator(destination: .custom(dir))
        let input = dir.appending(path: "Été à la plage 🌞.heic")

        let first = try locator.commit(baseName: input.baseName, fileExtension: "jpg", for: input, write: write("1"))
        let second = try locator.commit(baseName: input.baseName, fileExtension: "jpg", for: input, write: write("2"))

        XCTAssertEqual(first.lastPathComponent, "Été à la plage 🌞.jpg")
        XCTAssertEqual(second.lastPathComponent, "Été à la plage 🌞 2.jpg")
    }

    func testFailedWriteLeavesNothingBehind() throws {
        let dir = try Fixtures.directory(for: self)
        let locator = OutputLocator(destination: .custom(dir))

        XCTAssertThrowsError(try locator.commit(baseName: "x", fileExtension: "png", for: dir.appending(path: "x.jpg")) { url in
            try Data("partial".utf8).write(to: url)
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertEqual(try contents(dir), [])
    }

    func testOutputGetsTheInputCreationDate() throws {
        let dir = try Fixtures.directory(for: self)
        var input = dir.appending(path: "x.jpg")
        try Data("in".utf8).write(to: input)
        var values = URLResourceValues()
        values.creationDate = Date(timeIntervalSince1970: 1_000_000_000)
        try input.setResourceValues(values)

        let output = try OutputLocator(destination: .custom(dir.appending(path: "out")))
            .commit(baseName: "x", fileExtension: "png", for: input, write: write("1"))

        XCTAssertEqual(try output.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       Date(timeIntervalSince1970: 1_000_000_000))
    }

    func testMakeFolderPicksAFreeName() throws {
        let dir = try Fixtures.directory(for: self)
        let locator = OutputLocator(destination: .custom(dir))
        let input = dir.appending(path: "doc.pdf")

        XCTAssertEqual(try locator.makeFolder(baseName: "doc", for: input).lastPathComponent, "doc")
        XCTAssertEqual(try locator.makeFolder(baseName: "doc", for: input).lastPathComponent, "doc 2")
    }
}
