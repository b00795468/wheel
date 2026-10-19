import XCTest

final class OperationRegistryTests: XCTestCase {
    private let registry = OperationRegistry.standard

    private func ids(_ paths: [String], _ kind: WheelMode = .convert) -> [String] {
        let urls = paths.map { URL(fileURLWithPath: "/tmp/\($0)", isDirectory: $0.hasSuffix("/")) }
        return registry.operations(for: urls, kind: kind).map(\.id)
    }

    func testAnImageOffersEveryOtherFormat() {
        XCTAssertEqual(ids(["a.png"]), ["convert.jpg", "convert.heic", "convert.webp", "convert.tiff", "convert.pdf"])
        XCTAssertEqual(ids(["a.JPG"]), ["convert.png", "convert.heic", "convert.webp", "convert.tiff", "convert.pdf"])
        XCTAssertEqual(ids(["a.webp"]), ["convert.jpg", "convert.png", "convert.heic", "convert.tiff", "convert.pdf"])
        XCTAssertFalse(ids(["a.heif"]).contains("convert.heic"))
    }

    func testAVIFAndBMPAreAcceptedInputs() {
        for name in ["a.avif", "a.bmp"] {
            XCTAssertEqual(ids([name]), ["convert.jpg", "convert.png", "convert.heic", "convert.webp", "convert.tiff",
                                         "convert.pdf"], name)
        }
    }

    func testPDFOffersPNGAndJPGOnly() {
        XCTAssertEqual(ids(["a.pdf"]), ["convert.jpg", "convert.png"])
    }

    func testVideosOfferTheOtherVideoFormatsAndTheirSoundtrack() {
        XCTAssertEqual(ids(["a.mp4"]), ["convert.mov", "convert.gif", "convert.mp3", "convert.m4a"])
        XCTAssertEqual(ids(["a.mov"]), ["convert.mp4", "convert.gif", "convert.mp3", "convert.m4a"])
        for name in ["a.mkv", "a.webm", "a.avi"] {
            XCTAssertEqual(ids([name]), ["convert.mp4", "convert.mov", "convert.gif", "convert.mp3", "convert.m4a"], name)
        }
    }

    func testAudioOffersTheOtherAudioFormats() {
        XCTAssertEqual(ids(["a.mp3"]), ["convert.m4a", "convert.wav", "convert.flac"])
        XCTAssertEqual(ids(["a.m4a"]), ["convert.mp3", "convert.wav", "convert.flac"])
        XCTAssertEqual(ids(["a.wav"]), ["convert.mp3", "convert.m4a", "convert.flac"])
        XCTAssertEqual(ids(["a.flac"]), ["convert.mp3", "convert.m4a", "convert.wav"])
        for name in ["a.aiff", "a.ogg"] {
            XCTAssertEqual(ids([name]), ["convert.mp3", "convert.m4a", "convert.wav", "convert.flac"], name)
        }
    }

    func testSeveralFilesGetTheIntersection() {
        XCTAssertEqual(ids(["a.jpg", "b.png"]), ["convert.heic", "convert.webp", "convert.tiff", "convert.pdf"])
        XCTAssertEqual(ids(["a.pdf", "b.png"]), ["convert.jpg"])
        XCTAssertEqual(ids(["a.mp4", "b.wav"]), ["convert.mp3", "convert.m4a"])
        XCTAssertEqual(ids(["a.png", "b.mp4"]), [])
    }

    func testFoldersAndUnknownTypesGetNoConversion() {
        XCTAssertEqual(ids(["Vacances/"]), [])
        XCTAssertEqual(ids(["a.png", "Vacances/"]), [])
        XCTAssertEqual(ids(["notes.txt"]), [])
        XCTAssertEqual(ids(["anim.gif"]), [])
    }

    func testCompressIsOfferedForCompressibleFiles() {
        XCTAssertEqual(ids(["a.pdf"], .tools), ["tool.compress"])
        XCTAssertTrue(ids(["a.png"], .tools).contains("tool.compress"))
        XCTAssertFalse(ids(["a.bmp"], .tools).contains("tool.compress"))
        XCTAssertEqual(ids(["a.mp3"], .tools), [])
        XCTAssertEqual(ids(["Vacances/"], .tools), [])
    }

    func testIDsAreUniqueAndLookupWorks() {
        let all = registry.operations.map(\.id)
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertEqual(registry.operation(withID: "convert.png")?.title, "PNG")
        XCTAssertEqual(registry.operation(withID: "convert.mp4")?.title, "MP4")
        XCTAssertNil(registry.operation(withID: "nope"))
    }

    func testEachFileTypeFitsOnOnePage() {
        for name in ["a.png", "a.avif", "a.pdf", "a.mkv", "a.ogg"] {
            XCTAssertLessThanOrEqual(ids([name]).count, WheelModel.maxItemsPerPage, name)
        }
    }

    func testOnlyAudioAndVideoUseTheMediaEngineSlots() {
        XCTAssertEqual(registry.operation(withID: "convert.mp4")?.usesMediaEngine, true)
        XCTAssertEqual(registry.operation(withID: "convert.flac")?.usesMediaEngine, true)
        XCTAssertEqual(registry.operation(withID: "convert.webp")?.usesMediaEngine, false)
        XCTAssertEqual(registry.operation(withID: "convert.png")?.usesMediaEngine, false)
    }
}
