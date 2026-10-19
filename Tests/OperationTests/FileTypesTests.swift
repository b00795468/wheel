import UniformTypeIdentifiers
import XCTest

final class FileTypesTests: XCTestCase {
    private func type(_ path: String) -> UTType {
        FileTypes.type(of: URL(fileURLWithPath: path, isDirectory: path.hasSuffix("/")))
    }

    func testTypeComesFromTheExtensionWhateverItsCase() {
        XCTAssertEqual(type("/x/photo.JPG"), .jpeg)
        XCTAssertEqual(type("/x/photo.jpeg"), .jpeg)
        XCTAssertEqual(type("/x/scan.pdf"), .pdf)
    }

    func testFoldersAndUnknownFiles() {
        XCTAssertEqual(type("/x/Vacances/"), .folder)
        XCTAssertEqual(type("/x/sans-extension"), .data)
    }

    func testEverySpecImageInputIsAnImage() {
        for ext in ["jpg", "png", "heic", "heif", "webp", "tiff", "avif", "bmp"] {
            XCTAssertTrue(FileTypes.isImage(type("/x/a.\(ext)")), ext)
        }
        XCTAssertFalse(FileTypes.isImage(type("/x/a.pdf")))
        XCTAssertFalse(FileTypes.isImage(type("/x/a.gif")), "GIF is a video format here (§5.4)")
    }

    func testSameFormatDetection() {
        XCTAssertTrue(ImageFormat.jpeg.isSameFormat(as: type("/x/a.JPEG")))
        XCTAssertTrue(ImageFormat.heic.isSameFormat(as: type("/x/a.heif")))
        XCTAssertFalse(ImageFormat.png.isSameFormat(as: type("/x/a.jpg")))
    }

    func testBaseName() {
        XCTAssertEqual(URL(fileURLWithPath: "/x/Été 🌞.photo.heic").baseName, "Été 🌞.photo")
    }

    func testVideoAndAudioInputs() {
        for ext in ["mp4", "mov", "mkv", "webm", "avi"] {
            XCTAssertTrue(FileTypes.isVideo(type("/x/a.\(ext)")), ext)
            XCTAssertFalse(FileTypes.isAudio(type("/x/a.\(ext)")), ext)
        }
        for ext in ["mp3", "m4a", "wav", "flac", "aiff", "aif", "ogg"] {
            XCTAssertTrue(FileTypes.isAudio(type("/x/a.\(ext)")), ext)
            XCTAssertFalse(FileTypes.isVideo(type("/x/a.\(ext)")), ext)
        }
        XCTAssertFalse(FileTypes.isVideo(type("/x/a.gif")))
    }
}
