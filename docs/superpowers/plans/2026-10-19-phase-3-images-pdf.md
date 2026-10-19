# Phase 3 — Registre + conversions images & PDF — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Ce projet impose `superpowers:executing-plans` (voir CLAUDE.md, section Skills).

**Goal :** déposer une image ou un PDF sur un segment de la roue « Convertir » produit réellement le fichier converti dans `~/Downloads/Convertis/`, avec une pastille HUD de confirmation.

**Architecture :** un protocole `FileOperation` et un `OperationRegistry` décident des segments à partir du seul type déduit de l'URL (aucune lecture du fichier avant le drop, sinon invite de confidentialité). Les convertisseurs (ImageIO pour les images, PDFKit / Core Graphics pour les PDF) écrivent via un `OutputLocator` (nom libre, écriture temporaire puis déplacement atomique). Un `JobQueue` exécute hors du thread principal et pilote un `HUDController` (pastilles en bas à droite).

**Tech stack :** Swift 5 (mode de langage du projet), AppKit, ImageIO, PDFKit, Core Graphics, UniformTypeIdentifiers, XCTest. Aucune dépendance externe.

**Spec :** `SPEC.md` (§3, §4, §5.2, §5.4, §5.5, §5.6, §7, §9 phase 3).

## Contraintes globales

- macOS 14.0+, arm64 uniquement ; zéro package Swift externe (§1.4, §3).
- Interface en français ; code, types et commentaires en anglais (§1.6).
- Jamais d'écrasement, jamais de modification de l'original ; écriture temporaire puis déplacement atomique (§5.5).
- Dossier par défaut `~/Downloads/Convertis/`, créé si absent ; collision → `nom 2.ext`, `nom 3.ext`… (§5.5).
- Options de destination prévues : dossier Convertis, « À côté de l'original », dossier personnalisé (UI en phase 6).
- Métadonnées utiles conservées, orientation EXIF corrigée ; GPS retiré seulement si l'option est cochée (désactivée par défaut) (§5.5).
- Entrées images : JPG, PNG, HEIC, WebP, TIFF, AVIF, BMP. Sorties : JPG, PNG, HEIC, TIFF, PDF. **WebP en sortie : phase 4** (ImageIO ne sait pas l'encoder — vérifié : `CGImageDestinationCopyTypeIdentifiers` ne contient pas `org.webmproject.webp`).
- PDF → PNG / JPG, toutes les pages, 300 DPI ; une page → un fichier, plusieurs → sous-dossier (§5.4).
- Plusieurs images → un PDF multipage, dans l'ordre du drag (§5.4).
- Ne jamais proposer la conversion vers le format d'origine ; plusieurs fichiers → intersection ; dossiers → aucune conversion (§5.2, §5.4).
- Roue sans conversion : message neutre « Aucune conversion pour ce type » (§5.2).
- HUD : pastille près du coin bas-droit, « photo.png créé », clic → Finder, disparaît après 3 s ; tâche > 1 s → barre de progression + annulation (§5.6).
- Erreurs en français humain, jamais de trace technique ; log technique dans `~/Library/Logs/<NomApp>/` ; son discret désactivable (§5.6).
- Aucune lecture du fichier glissé avant le drop (invite « Bureau » constatée en phase 2).

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `App/Operations/FileTypes.swift` (nouveau) | Type d'un fichier d'après son URL ; familles image / PDF ; `URL.baseName` |
| `App/Operations/FileOperation.swift` (nouveau) | Protocole `FileOperation`, `OperationContext`, `OperationError` |
| `App/Operations/OperationRegistry.swift` (nouveau) | Catalogue, intersection multi-fichiers, recherche par id |
| `App/Operations/Converters/ImageFormat.swift` (nouveau) | Formats de sortie natifs (JPG, PNG, HEIC, TIFF) |
| `App/Operations/Converters/ImageConverter.swift` (nouveau) | Décodage redressé, métadonnées, aplatissement, encodage |
| `App/Operations/Converters/PDFConverter.swift` (nouveau) | Images → PDF, rendu des pages à 300 DPI |
| `App/Operations/Converters/ConvertToImageOperation.swift` (nouveau) | Opération « vers JPG/PNG/HEIC/TIFF » |
| `App/Operations/Converters/ImagesToPDFOperation.swift` (nouveau) | Opération « PDF » |
| `App/Output/OutputLocator.swift` (nouveau) | Dossier de sortie, nom libre, écriture atomique, date de création |
| `App/Output/JobQueue.swift` (nouveau) | Exécution en tâche de fond, annulation, issue → HUD, son, log |
| `App/Feedback/HUDToast.swift` (nouveau) | `HUDController` + pastille (progression, succès, erreur) |
| `App/Feedback/TechnicalLog.swift` (nouveau) | Journal technique fichier |
| `App/Settings/SettingsStore.swift` | Destination, retrait GPS, son (lecture seule jusqu'en phase 6) |
| `App/AppInfo.swift` | Logger `jobs` |
| `App/Wheel/WheelModel.swift` | `WheelMode.emptyMessage` ; suppression de `PlaceholderSegments` |
| `App/Wheel/WheelView.swift` | Message de roue vide ; icône via `FileTypes` |
| `App/Wheel/WheelController.swift` | Segments fournis de l'extérieur ; callback de drop |
| `App/GestureCoordinator.swift` | Registre + JobQueue ; argument debug `-debugRun` |
| `App/AppDelegate.swift` | Appel des arguments debug |
| `project.yml` | Sources du target de tests |
| `Tests/Support/Fixtures.swift` (nouveau) | Fixtures générées en code (images, PDF), lecture de pixels |
| `Tests/OperationTests/*.swift` (nouveaux) | Types, convertisseurs, registre, opérations |
| `Tests/OutputLocatorTests/OutputLocatorTests.swift` (nouveau) | Nommage, collisions, destinations, atomicité |

Les commandes de test : `scripts/test.sh` (régénère le projet, lance tous les tests, affiche « Executed N tests »). Build : `scripts/build.sh Debug`.

---

### Task 1 : Types de fichiers et formats de sortie

**Files :**
- Create : `App/Operations/FileTypes.swift`, `App/Operations/Converters/ImageFormat.swift`
- Create : `Tests/OperationTests/FileTypesTests.swift`
- Modify : `project.yml` (sources de PivotTests), `App/Wheel/WheelView.swift` (icône du centre)

**Interfaces :**
- Produces : `FileTypes.type(of: URL) -> UTType`, `FileTypes.isImage(_: UTType) -> Bool`, `FileTypes.isPDF(_: UTType) -> Bool`, `FileTypes.imageInputs`, `URL.baseName`, `ImageFormat` (`.jpeg`, `.png`, `.heic`, `.tiff`, `isSameFormat(as:)`, `type`, `fileExtension`, `title`, `symbol`, `supportsAlpha`, `lossyQuality`).

- [ ] **Step 1 : ajouter les sources au target de tests** — dans `project.yml`, la liste `sources` de `PivotTests` devient :

```yaml
    sources:
      - Tests
      - App/DragMonitor/ModifierTapDetector.swift
      - App/Wheel/WheelModel.swift
      - App/Wheel/WheelGeometry.swift
      - App/Wheel/WheelView.swift
      - App/Theme.swift
      - App/Operations
```

(`App/Output/OutputLocator.swift` s'ajoute à cette liste en tâche 2, une fois le fichier créé : XcodeGen refuse une source absente.)

- [ ] **Step 2 : écrire les tests** — `Tests/OperationTests/FileTypesTests.swift` :

```swift
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
}
```

- [ ] **Step 3 : lancer les tests, vérifier l'échec** — `scripts/test.sh` → échec de compilation (`cannot find 'FileTypes' in scope`).

- [ ] **Step 4 : implémenter** — `App/Operations/FileTypes.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// File type detection from the URL alone. The wheel picks its segments
/// while the drag is still in flight, before the drop grants access to the
/// file, so nothing here may read it (reading triggers privacy prompts).
enum FileTypes {
    /// Declared by macOS 14+ (ImageIO reads and writes AVIF).
    static let avif = UTType("public.avif")!

    /// Image formats accepted as input (§5.4).
    static let imageInputs: [UTType] = [.jpeg, .png, .heic, .heif, .webP, .tiff, avif, .bmp]

    static func type(of url: URL) -> UTType {
        if url.hasDirectoryPath { return .folder }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    static func isImage(_ type: UTType) -> Bool {
        imageInputs.contains { type.conforms(to: $0) }
    }

    static func isPDF(_ type: UTType) -> Bool {
        type.conforms(to: .pdf)
    }
}

extension URL {
    /// File name without its extension: "photo" for "photo.heic".
    var baseName: String { deletingPathExtension().lastPathComponent }
}
```

`App/Operations/Converters/ImageFormat.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// An output image format ImageIO can encode natively (§3). WebP is not
/// one: ImageIO cannot encode it, it comes with the embedded ffmpeg (phase 4).
struct ImageFormat: Equatable, Sendable {
    let type: UTType
    let fileExtension: String
    let title: String
    let symbol: String
    let supportsAlpha: Bool
    /// Encoder quality for lossy formats, nil for lossless ones.
    let lossyQuality: Double?
    /// Input types that already are this format: no X → X conversion (§5.4).
    let sameFormatTypes: [UTType]

    func isSameFormat(as input: UTType) -> Bool {
        sameFormatTypes.contains { input.conforms(to: $0) }
    }

    static let jpeg = ImageFormat(type: .jpeg, fileExtension: "jpg", title: "JPG", symbol: "photo",
                                  supportsAlpha: false, lossyQuality: 0.9, sameFormatTypes: [.jpeg])
    static let png = ImageFormat(type: .png, fileExtension: "png", title: "PNG", symbol: "photo.fill",
                                 supportsAlpha: true, lossyQuality: nil, sameFormatTypes: [.png])
    static let heic = ImageFormat(type: .heic, fileExtension: "heic", title: "HEIC", symbol: "photo.on.rectangle",
                                  supportsAlpha: true, lossyQuality: 0.9, sameFormatTypes: [.heic, .heif])
    static let tiff = ImageFormat(type: .tiff, fileExtension: "tiff", title: "TIFF", symbol: "doc.richtext",
                                  supportsAlpha: true, lossyQuality: nil, sameFormatTypes: [.tiff])
}
```

Dans `App/Wheel/WheelView.swift`, `WheelCenterView.setFiles` utilise `FileTypes` et la fonction privée `contentType(of:)` (avec son commentaire) est supprimée :

```swift
        icon.image = NSWorkspace.shared.icon(for: FileTypes.type(of: first))
```

- [ ] **Step 5 : lancer les tests** — `scripts/test.sh` → `TESTS OK`.
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 3: file type detection and native image formats"`.

---

### Task 2 : OutputLocator (dossier, nom libre, écriture atomique)

**Files :**
- Create : `App/Output/OutputLocator.swift`, `Tests/Support/Fixtures.swift`, `Tests/OutputLocatorTests/OutputLocatorTests.swift`

**Interfaces :**
- Produces : `enum OutputDestination { case convertedFolder, besideOriginal, custom(URL) }` ; `struct OutputLocator(destination:convertedFolder:)` ; `directory(for:) throws -> URL` ; `static availableURL(in:baseName:fileExtension:) -> URL` ; `commit(baseName:fileExtension:for:write:) throws -> URL` ; `makeFolder(baseName:for:) throws -> URL` ; `static defaultConvertedFolder`.
- Produces (tests) : `Fixtures.directory(for:)`, `Fixtures.makeCGImage`, `Fixtures.writeImage`, `Fixtures.writePDF`, `Fixtures.info`, `Fixtures.pixel`, `Fixtures.isRed`, `Fixtures.isWhite`.

- [ ] **Step 0 : sources de test** — ajouter `      - App/Output/OutputLocator.swift` à la fin de la liste `sources` de `PivotTests` dans `project.yml` (créer d'abord le fichier vide `App/Output/OutputLocator.swift`).

- [ ] **Step 1 : fixtures** — `Tests/Support/Fixtures.swift` :

```swift
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

/// Test files generated in code, so the suite needs no checked-in binaries.
enum Fixtures {
    struct ImageInfo {
        let type: String
        let width: Int
        let height: Int
        let properties: [CFString: Any]
        let image: CGImage
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    private static let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// Fresh empty folder, deleted when the test ends.
    static func directory(for test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PivotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Blue image (transparent when `alpha`) with a red 10×10 block in its
    /// top-left corner, to check orientation after conversion.
    static func makeCGImage(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: info.rawValue)!
        let all = CGRect(x: 0, y: 0, width: width, height: height)
        if alpha {
            context.clear(all)
        } else {
            context.setFillColor(blue)
            context.fill(all)
        }
        context.setFillColor(red)
        context.fill(CGRect(x: 0, y: height - 10, width: 10, height: 10))
        return context.makeImage()!
    }

    @discardableResult
    static func writeImage(_ name: String, in directory: URL, type: UTType, width: Int = 40, height: Int = 20,
                           alpha: Bool = false, orientation: Int = 1, gps: Bool = false, dpi: Double? = nil) throws -> URL {
        let url = directory.appending(path: name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 48.85, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.35, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(destination, makeCGImage(width: width, height: height, alpha: alpha),
                                   properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// PDF whose pages have the given sizes (points), each with a red
    /// 50×50 square in its top-left corner. `rotations` applies per page.
    @discardableResult
    static func writePDF(_ name: String, in directory: URL, pages: [CGSize], rotations: [Int] = [],
                         password: String? = nil) throws -> URL {
        let data = NSMutableData()
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: nil, nil)!
        for size in pages {
            var box = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &box)
            context.setFillColor(red)
            context.fill(CGRect(x: 0, y: size.height - 50, width: 50, height: 50))
            context.endPage()
        }
        context.closePDF()

        let document = PDFDocument(data: data as Data)!
        for (index, rotation) in rotations.enumerated() {
            document.page(at: index)?.rotation = rotation
        }
        var options: [PDFDocumentWriteOption: Any] = [:]
        if let password {
            options[.userPasswordOption] = password
            options[.ownerPasswordOption] = password
        }
        let url = directory.appending(path: name)
        guard document.write(to: url, withOptions: options) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func info(_ url: URL) throws -> ImageInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return ImageInfo(type: type, width: image.width, height: image.height, properties: properties, image: image)
    }

    /// RGBA of the pixel at (x, y), counted from the top-left corner.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let flippedY = image.height - 1 - y
            context.draw(image, in: CGRect(x: -x, y: -flippedY, width: image.width, height: image.height))
        }
        return data
    }

    static func isRed(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] < 70 && pixel[2] < 70 }
    static func isWhite(_ pixel: [UInt8]) -> Bool { pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240 }
}
```

- [ ] **Step 2 : tests** — `Tests/OutputLocatorTests/OutputLocatorTests.swift` :

```swift
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
```

- [ ] **Step 3 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'OutputLocator' in scope`.

- [ ] **Step 4 : implémenter** — `App/Output/OutputLocator.swift` :

```swift
import Foundation

/// Where converted files go (§5.5). Chosen in Settings from phase 6.
enum OutputDestination: Equatable, Sendable {
    case convertedFolder
    case besideOriginal
    case custom(URL)
}

/// Picks the output folder and a free name, and writes results atomically:
/// into a temporary file first, then moved under a name that does not
/// exist yet. Never overwrites, never touches the original (§5.5).
struct OutputLocator: Sendable {
    /// ~/Downloads/Convertis
    static let defaultConvertedFolder = URL.downloadsDirectory
        .appending(path: "Convertis", directoryHint: .isDirectory)

    let destination: OutputDestination
    var convertedFolder: URL = Self.defaultConvertedFolder

    /// Folder receiving the outputs of `input`, created if missing.
    func directory(for input: URL) throws -> URL {
        let directory: URL = switch destination {
        case .convertedFolder: convertedFolder
        case .besideOriginal: input.deletingLastPathComponent()
        case .custom(let folder): folder
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// First free name among "<base>.<ext>", "<base> 2.<ext>", "<base> 3.<ext>"…
    /// A nil extension names a folder.
    static func availableURL(in directory: URL, baseName: String, fileExtension: String?) -> URL {
        var number = 1
        while true {
            let name = number == 1 ? baseName : "\(baseName) \(number)"
            let url = directory.appending(path: fileExtension.map { "\(name).\($0)" } ?? name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }

    /// Lets `write` produce the file at a temporary URL on the same volume,
    /// then moves it to a free name and gives it the input's creation date.
    func commit(baseName: String, fileExtension: String, for input: URL,
                write: (URL) throws -> Void) throws -> URL {
        let directory = try directory(for: input)
        let fileManager = FileManager.default
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: directory, create: true)
        defer { try? fileManager.removeItem(at: staging) }
        let temporary = staging.appending(path: "\(baseName).\(fileExtension)")
        try write(temporary)

        // Another job may take the same name between the check and the move.
        while true {
            let target = Self.availableURL(in: directory, baseName: baseName, fileExtension: fileExtension)
            do {
                try fileManager.moveItem(at: temporary, to: target)
                Self.copyCreationDate(from: input, to: target)
                return target
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
    }

    /// Creates an empty folder under a free name, for multi-file results.
    func makeFolder(baseName: String, for input: URL) throws -> URL {
        let directory = try directory(for: input)
        while true {
            let folder = Self.availableURL(in: directory, baseName: baseName, fileExtension: nil)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                return folder
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
    }

    private static func copyCreationDate(from input: URL, to output: URL) {
        guard let date = try? input.resourceValues(forKeys: [.creationDateKey]).creationDate else { return }
        var values = URLResourceValues()
        values.creationDate = date
        var output = output
        try? output.setResourceValues(values)
    }
}
```

- [ ] **Step 5 : lancer les tests** — `scripts/test.sh` → `TESTS OK`.
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 3: OutputLocator with free names and atomic writes"`.

---

### Task 3 : Protocole d'opération et convertisseur d'images

**Files :**
- Create : `App/Operations/FileOperation.swift`, `App/Operations/Converters/ImageConverter.swift`, `Tests/OperationTests/ImageConverterTests.swift`

**Interfaces :**
- Consumes : `ImageFormat`, `OutputLocator`, `WheelMode`, `WheelSegment`.
- Produces : `protocol FileOperation: Sendable` (`id`, `kind: WheelMode`, `title`, `symbol`, `accepts(_ types: [UTType]) -> Bool`, `run(inputs:context:progress:) async throws -> [URL]`, `segment`) ; `struct OperationContext(output: OutputLocator, stripsLocation: Bool)` ; `struct OperationError` (`.unreadableImage`, `.unreadablePDF`, `.lockedPDF`, `.writeFailed`, `message`) ; `ImageConverter.convert(_:to:destination:stripsLocation:)`, `ImageConverter.write(_:as:to:properties:)`, `ImageConverter.uprightImage(from:)`, `ImageConverter.metadata(of:stripsLocation:)`, `ImageConverter.flattenedOnWhite(_:)`.

- [ ] **Step 1 : tests** — `Tests/OperationTests/ImageConverterTests.swift` :

```swift
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ImageConverterTests: XCTestCase {
    private func convert(_ input: URL, to format: ImageFormat, stripsLocation: Bool = false) throws -> URL {
        let output = input.deletingLastPathComponent()
            .appending(path: "out-\(UUID().uuidString).\(format.fileExtension)")
        try ImageConverter.convert(input, to: format, destination: output, stripsLocation: stripsLocation)
        return output
    }

    func testEachFormatIsWrittenWithItsRealType() throws {
        let dir = try Fixtures.directory(for: self)
        let png = try Fixtures.writeImage("a.png", in: dir, type: .png)
        let jpg = try Fixtures.writeImage("b.jpg", in: dir, type: .jpeg)
        for (input, format) in [(png, ImageFormat.jpeg), (png, .heic), (png, .tiff), (jpg, .png)] {
            let info = try Fixtures.info(try convert(input, to: format))
            XCTAssertEqual(info.type, format.type.identifier, format.title)
            XCTAssertEqual([info.width, info.height], [40, 20], format.title)
        }
    }

    func testAVIFAndBMPInputsAreRead() throws {
        let dir = try Fixtures.directory(for: self)
        for (name, type) in [("a.avif", FileTypes.avif), ("a.bmp", UTType.bmp)] {
            let input = try Fixtures.writeImage(name, in: dir, type: type)
            XCTAssertEqual(try Fixtures.info(try convert(input, to: .png)).type, UTType.png.identifier, name)
        }
    }

    func testOrientationIsAppliedToThePixels() throws {
        let dir = try Fixtures.directory(for: self)
        // Stored 40×20 with red top-left; orientation 6 = shown rotated 90° clockwise.
        let input = try Fixtures.writeImage("rotated.jpg", in: dir, type: .jpeg, orientation: 6)

        let info = try Fixtures.info(try convert(input, to: .png))

        XCTAssertEqual([info.width, info.height], [20, 40])
        XCTAssertEqual(info.properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(info.image, x: 17, y: 2)), "red block should now be top-right")
    }

    func testTransparencyBecomesWhiteInJPEG() throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("alpha.png", in: dir, type: .png, alpha: true)

        let info = try Fixtures.info(try convert(input, to: .jpeg))

        XCTAssertTrue(Fixtures.isWhite(Fixtures.pixel(info.image, x: 30, y: 15)))
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(info.image, x: 3, y: 3)))
    }

    func testLocationIsKeptByDefaultAndStrippedOnRequest() throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("gps.jpg", in: dir, type: .jpeg, gps: true)

        let kept = try Fixtures.info(try convert(input, to: .heic))
        let stripped = try Fixtures.info(try convert(input, to: .heic, stripsLocation: true))

        XCTAssertNotNil(kept.properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(stripped.properties[kCGImagePropertyGPSDictionary])
    }

    func testUnreadableImageThrowsAHumanError() throws {
        let dir = try Fixtures.directory(for: self)
        let input = dir.appending(path: "bad.jpg")
        try Data("not an image".utf8).write(to: input)

        XCTAssertThrowsError(try convert(input, to: .png)) { error in
            XCTAssertEqual(error as? OperationError, .unreadableImage)
        }
    }
}
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'ImageConverter' in scope`.

- [ ] **Step 3 : implémenter** — `App/Operations/FileOperation.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// What an operation needs besides its inputs.
struct OperationContext: Sendable {
    let output: OutputLocator
    /// Drop GPS metadata from images (§5.5, off by default).
    let stripsLocation: Bool
}

/// One segment of a wheel. Adding a format means adding an operation to
/// `OperationRegistry.standard`, without touching the wheel (§4).
protocol FileOperation: Sendable {
    /// Stable identifier, e.g. "convert.png".
    var id: String { get }
    var kind: WheelMode { get }
    var title: String { get }
    var symbol: String { get }
    /// Whether the operation applies to files of all these types at once.
    func accepts(_ types: [UTType]) -> Bool
    /// Runs off the main thread. Returns the created files or folders.
    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL]
}

extension FileOperation {
    var segment: WheelSegment { WheelSegment(id: id, title: title, symbol: symbol) }
}

/// A failure the HUD can show as is: French, human, no jargon (§5.6).
struct OperationError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }

    static let unreadableImage = OperationError(message: "Cette image semble corrompue ou illisible.")
    static let unreadablePDF = OperationError(message: "Ce PDF semble corrompu ou illisible.")
    static let lockedPDF = OperationError(message: "Ce PDF est protégé par un mot de passe.")
    static let writeFailed = OperationError(message: "Impossible d'enregistrer le fichier converti.")
}
```

`App/Operations/Converters/ImageConverter.swift` :

```swift
import CoreGraphics
import Foundation
import ImageIO

/// Image decoding and encoding with ImageIO (§3).
enum ImageConverter {
    /// Converts the first image of `input` to `format` at `destination`.
    static func convert(_ input: URL, to format: ImageFormat, destination: URL, stripsLocation: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = uprightImage(from: source) else {
            throw OperationError.unreadableImage
        }
        try write(image, as: format, to: destination,
                  properties: metadata(of: source, stripsLocation: stripsLocation))
    }

    /// Encodes `image`, flattening transparency on white for formats without alpha.
    static func write(_ image: CGImage, as format: ImageFormat, to destination: URL,
                      properties: [CFString: Any] = [:]) throws {
        let image = format.supportsAlpha ? image : (flattenedOnWhite(image) ?? image)
        var properties = properties
        if let quality = format.lossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL,
                                                           format.type.identifier as CFString, 1, nil) else {
            throw OperationError.writeFailed
        }
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw OperationError.writeFailed }
    }

    /// First image of `source` with its EXIF orientation applied to the
    /// pixels, so every output (PDF included) shows it the right way up.
    static func uprightImage(from source: CGImageSource) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        guard orientation != 1 else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }

        // The thumbnail API is the ImageIO way to apply the orientation;
        // asking for the full size makes it a full-resolution decode.
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Metadata worth keeping (EXIF, IPTC, TIFF, GPS, resolution), with the
    /// orientation reset since `uprightImage` already applied it.
    static func metadata(of source: CGImageSource, stripsLocation: Bool) -> [CFString: Any] {
        let all = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let keys = [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyGPSDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
        var kept: [CFString: Any] = [:]
        for key in keys {
            kept[key] = all[key]
        }
        kept[kCGImagePropertyOrientation] = 1
        if var tiff = kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            kept[kCGImagePropertyTIFFDictionary] = tiff
        }
        if stripsLocation {
            kept[kCGImagePropertyGPSDictionary] = nil
        }
        return kept
    }

    /// Composites `image` over white; JPEG would otherwise turn transparency black.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
```

- [ ] **Step 4 : lancer les tests** — `scripts/test.sh` → `TESTS OK`. Si `testLocationIsKeptByDefault…` échoue sur le GPS conservé en HEIC, refaire le test en sortie TIFF avant de toucher au code (vérifier d'abord quel format perd le GPS — systematic-debugging).
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 3: FileOperation protocol and ImageIO converter"`.

---

### Task 4 : Convertisseur PDF

**Files :**
- Create : `App/Operations/Converters/PDFConverter.swift`, `Tests/OperationTests/PDFConverterTests.swift`

**Interfaces :**
- Consumes : `ImageConverter.uprightImage(from:)`, `ImageConverter.write(_:as:to:properties:)`, `OutputLocator.commit`, `OutputLocator.makeFolder`, `OperationError`, `URL.baseName`.
- Produces : `PDFConverter.makePDF(from:destination:progress:)`, `PDFConverter.pageSize(of:source:)`, `PDFConverter.openDocument(_:)`, `PDFConverter.render(_:)`, `PDFConverter.renderPages(of:as:output:progress:) throws -> URL`, `PDFConverter.renderDPI`.

- [ ] **Step 1 : tests** — `Tests/OperationTests/PDFConverterTests.swift` :

```swift
import PDFKit
import XCTest

final class PDFConverterTests: XCTestCase {
    func testImagesBecomeOnePDFInDragOrder() throws {
        let dir = try Fixtures.directory(for: self)
        let wide = try Fixtures.writeImage("a.png", in: dir, type: .png, width: 40, height: 20)
        let tall = try Fixtures.writeImage("b.jpg", in: dir, type: .jpeg, width: 20, height: 40)
        let output = dir.appending(path: "out.pdf")
        var steps: [Double] = []

        try PDFConverter.makePDF(from: [wide, tall], destination: output) { steps.append($0) }

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 40, height: 20))
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 20, height: 40))
        XCTAssertEqual(steps, [0.5, 1])
    }

    func testPageSizeFollowsTheImageResolution() throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("scan.png", in: dir, type: .png, width: 600, height: 300, dpi: 300)
        let output = dir.appending(path: "out.pdf")

        try PDFConverter.makePDF(from: [input], destination: output) { _ in }

        XCTAssertEqual(PDFDocument(url: output)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 144, height: 72))
    }

    func testSinglePagePDFGivesOneImageAt300DPI() throws {
        let dir = try Fixtures.directory(for: self)
        let pdf = try Fixtures.writePDF("a4.pdf", in: dir, pages: [CGSize(width: 595, height: 842)])
        let out = dir.appending(path: "out", directoryHint: .isDirectory)

        let result = try PDFConverter.renderPages(of: pdf, as: .png, output: OutputLocator(destination: .custom(out))) { _ in }

        XCTAssertEqual(result.lastPathComponent, "a4.png")
        let info = try Fixtures.info(result)
        XCTAssertEqual([info.width, info.height], [2479, 3508])
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(info.image, x: 20, y: 20)))
        XCTAssertTrue(Fixtures.isWhite(Fixtures.pixel(info.image, x: 1200, y: 1700)))
    }

    func testMultiPagePDFGivesAFolderOfNumberedPages() throws {
        let dir = try Fixtures.directory(for: self)
        let pdf = try Fixtures.writePDF("doc.pdf", in: dir, pages: Array(repeating: CGSize(width: 100, height: 100), count: 12))
        let out = dir.appending(path: "out", directoryHint: .isDirectory)

        let folder = try PDFConverter.renderPages(of: pdf, as: .jpeg, output: OutputLocator(destination: .custom(out))) { _ in }

        XCTAssertEqual(folder.lastPathComponent, "doc")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names.count, 12)
        XCTAssertEqual(names.first, "doc 01.jpg")
        XCTAssertEqual(names.last, "doc 12.jpg")
    }

    func testRotatedPageIsRenderedUpright() throws {
        let dir = try Fixtures.directory(for: self)
        // 200×100 pt page, red square top-left, displayed rotated 90° clockwise.
        let pdf = try Fixtures.writePDF("r.pdf", in: dir, pages: [CGSize(width: 200, height: 100)], rotations: [90])
        let out = dir.appending(path: "out", directoryHint: .isDirectory)

        let image = try Fixtures.info(try PDFConverter.renderPages(of: pdf, as: .png,
                                                                   output: OutputLocator(destination: .custom(out))) { _ in })

        XCTAssertEqual([image.width, image.height], [417, 833])
        XCTAssertTrue(Fixtures.isRed(Fixtures.pixel(image.image, x: image.width - 20, y: 20)), "top-left goes top-right")
    }

    func testLockedAndCorruptPDFsThrowHumanErrors() throws {
        let dir = try Fixtures.directory(for: self)
        let locked = try Fixtures.writePDF("locked.pdf", in: dir, pages: [CGSize(width: 100, height: 100)], password: "secret")
        let corrupt = dir.appending(path: "corrupt.pdf")
        try Data("not a pdf".utf8).write(to: corrupt)
        let locator = OutputLocator(destination: .custom(dir.appending(path: "out")))

        XCTAssertThrowsError(try PDFConverter.renderPages(of: locked, as: .png, output: locator) { _ in }) {
            XCTAssertEqual($0 as? OperationError, .lockedPDF)
        }
        XCTAssertThrowsError(try PDFConverter.renderPages(of: corrupt, as: .png, output: locator) { _ in }) {
            XCTAssertEqual($0 as? OperationError, .unreadablePDF)
        }
    }
}
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'PDFConverter' in scope`.

- [ ] **Step 3 : implémenter** — `App/Operations/Converters/PDFConverter.swift` :

```swift
import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// PDF reading and writing with PDFKit and Core Graphics (§3).
enum PDFConverter {
    static let renderDPI: CGFloat = 300
    /// Cap for very large pages (posters, plans), in pixels per side.
    static let maxRenderSide: CGFloat = 12_000

    /// One PDF with a page per image, in the given (drag) order.
    static func makePDF(from images: [URL], destination: URL, progress: (Double) -> Void) throws {
        guard let context = CGContext(destination as CFURL, mediaBox: nil, nil) else {
            throw OperationError.writeFailed
        }
        defer { context.closePDF() }
        for (index, url) in images.enumerated() {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = ImageConverter.uprightImage(from: source) else {
                throw OperationError.unreadableImage
            }
            var box = CGRect(origin: .zero, size: pageSize(of: image, source: source))
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
            progress(Double(index + 1) / Double(images.count))
        }
    }

    /// Page size in points from the image's own resolution (72 dpi if unknown).
    static func pageSize(of image: CGImage, source: CGImageSource) -> CGSize {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        return CGSize(width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
    }

    static func openDocument(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw OperationError.unreadablePDF }
        if document.isLocked { throw OperationError.lockedPDF }
        guard document.pageCount > 0 else { throw OperationError.unreadablePDF }
        return document
    }

    /// Renders a page on white at `renderDPI`, honouring its crop box and rotation.
    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let quarterTurn = (page.rotation / 90) % 2 != 0
        let size = quarterTurn ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min(renderDPI / 72, maxRenderSide / max(size.width, size.height, 1))
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }

    /// Renders every page of `pdf` as `format`: one file for a single page,
    /// otherwise a folder "<name>/<name> 01.png", "<name> 02.png"… (§5.4).
    static func renderPages(of pdf: URL, as format: ImageFormat, output: OutputLocator,
                            progress: (Double) -> Void) throws -> URL {
        let document = try openDocument(pdf)
        let base = pdf.baseName
        let count = document.pageCount
        let resolution: [CFString: Any] = [kCGImagePropertyDPIWidth: renderDPI, kCGImagePropertyDPIHeight: renderDPI]

        func writePage(_ index: Int, named name: String, with locator: OutputLocator) throws -> URL {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let image = render(page) else {
                throw OperationError.unreadablePDF
            }
            let url = try locator.commit(baseName: name, fileExtension: format.fileExtension, for: pdf) {
                try ImageConverter.write(image, as: format, to: $0, properties: resolution)
            }
            progress(Double(index + 1) / Double(count))
            return url
        }

        if count == 1 {
            return try writePage(0, named: base, with: output)
        }
        let folder = try output.makeFolder(baseName: base, for: pdf)
        let pages = OutputLocator(destination: .custom(folder))
        let digits = String(count).count
        do {
            for index in 0..<count {
                let number = String(index + 1)
                let padded = String(repeating: "0", count: digits - number.count) + number
                _ = try writePage(index, named: "\(base) \(padded)", with: pages)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }
}
```

- [ ] **Step 4 : lancer les tests** — `scripts/test.sh` → `TESTS OK`. En cas d'échec du test de rotation, vérifier d'abord si `PDFPage.draw(with:to:)` applique la rotation (systematic-debugging) avant de transformer le contexte à la main.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 3: PDF converter (images to PDF, pages at 300 DPI)"`.

---

### Task 5 : Opérations, registre, et roue branchée dessus

**Files :**
- Create : `App/Operations/Converters/ConvertToImageOperation.swift`, `App/Operations/Converters/ImagesToPDFOperation.swift`, `App/Operations/OperationRegistry.swift`
- Create : `Tests/OperationTests/OperationRegistryTests.swift`, `Tests/OperationTests/ConvertOperationTests.swift`
- Modify : `App/Wheel/WheelModel.swift`, `App/Wheel/WheelView.swift`, `App/Wheel/WheelController.swift`, `Tests/GestureTests/WheelModelTests.swift`, `Tests/GestureTests/WheelViewTests.swift`

**Interfaces :**
- Consumes : tout ce qui précède.
- Produces : `ConvertToImageOperation(format:acceptsPDF:)`, `ImagesToPDFOperation()`, `OperationRegistry.standard`, `operations(for: [URL], kind: WheelMode) -> [any FileOperation]`, `operation(withID:) -> (any FileOperation)?` ; `WheelMode.emptyMessage` ; `WheelView.setItems(_:emptyMessage:)` ; `WheelController.segmentsProvider: (WheelMode, [URL]) -> [WheelSegment]`, `WheelController.onDrop: ((String, [URL]) -> Void)?`.

- [ ] **Step 1 : tests du registre** — `Tests/OperationTests/OperationRegistryTests.swift` :

```swift
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
```

`Tests/OperationTests/ConvertOperationTests.swift` :

```swift
import PDFKit
import XCTest

/// Thread-safe progress sink for @Sendable callbacks.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func record(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}

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
```

Mettre à jour `Tests/GestureTests/WheelModelTests.swift` : supprimer `testPlaceholderWheelsFitOnOnePage` (remplacé par `testEveryWheelFitsOnOnePageForNow`).

Remplacer `Tests/GestureTests/WheelViewTests.swift` par :

```swift
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
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'OperationRegistry' in scope`.

- [ ] **Step 3 : implémenter les opérations** — `App/Operations/Converters/ConvertToImageOperation.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// "To <format>": images to another image format, and PDF pages to PNG or
/// JPG (§5.4). Never offered for a file that already has that format.
struct ConvertToImageOperation: FileOperation {
    let format: ImageFormat
    /// Only PNG and JPG are offered for PDFs (§5.4).
    let acceptsPDF: Bool

    var id: String { "convert.\(format.fileExtension)" }
    var kind: WheelMode { .convert }
    var title: String { format.title }
    var symbol: String { format.symbol }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { type in
            if FileTypes.isPDF(type) { return acceptsPDF }
            return FileTypes.isImage(type) && !format.isSameFormat(as: type)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share = { (fraction: Double) in progress((Double(index) + fraction) / Double(inputs.count)) }
            if FileTypes.isPDF(FileTypes.type(of: input)) {
                outputs.append(try PDFConverter.renderPages(of: input, as: format, output: context.output, progress: share))
            } else {
                outputs.append(try context.output.commit(baseName: input.baseName, fileExtension: format.fileExtension,
                                                         for: input) {
                    try ImageConverter.convert(input, to: format, destination: $0, stripsLocation: context.stripsLocation)
                })
            }
            share(1)
        }
        return outputs
    }
}
```

`App/Operations/Converters/ImagesToPDFOperation.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// "PDF": one PDF from one or several images, pages in drag order (§5.4).
struct ImagesToPDFOperation: FileOperation {
    let id = "convert.pdf"
    let kind = WheelMode.convert
    let title = "PDF"
    let symbol = "doc.text"

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(FileTypes.isImage)
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let first = inputs.first else { return [] }
        let pdf = try context.output.commit(baseName: first.baseName, fileExtension: "pdf", for: first) {
            try PDFConverter.makePDF(from: inputs, destination: $0, progress: progress)
        }
        return [pdf]
    }
}
```

`App/Operations/OperationRegistry.swift` :

```swift
import Foundation

/// Catalogue of every operation (§4). The order here is the order on the wheel.
struct OperationRegistry: Sendable {
    let operations: [any FileOperation]

    static let standard = OperationRegistry(operations: [
        ConvertToImageOperation(format: .jpeg, acceptsPDF: true),
        ConvertToImageOperation(format: .png, acceptsPDF: true),
        ConvertToImageOperation(format: .heic, acceptsPDF: false),
        ConvertToImageOperation(format: .tiff, acceptsPDF: false),
        ImagesToPDFOperation(),
    ])

    /// Operations of `kind` that apply to every one of `files` (§5.2).
    /// Only the URLs are used: the files are not readable before the drop.
    func operations(for files: [URL], kind: WheelMode) -> [any FileOperation] {
        let types = files.map(FileTypes.type(of:))
        return operations.filter { $0.kind == kind && $0.accepts(types) }
    }

    func operation(withID id: String) -> (any FileOperation)? {
        operations.first { $0.id == id }
    }
}
```

- [ ] **Step 4 : brancher la roue** — dans `App/Wheel/WheelModel.swift` : supprimer l'enum `PlaceholderSegments` entière, et ajouter dans `WheelMode` :

```swift
    /// Shown on the ring when no segment applies (§5.2).
    var emptyMessage: String {
        switch self {
        case .convert: "Aucune conversion pour ce type"
        case .tools: "Aucun outil pour ce type"
        case .actions: "Aucune action pour ce type"
        }
    }
```

Dans `App/Wheel/WheelView.swift`, classe `WheelView` : ajouter la propriété

```swift
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
```

à la fin de `init()` (après `addSubview(centerView)`) :

```swift
        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        let ringMiddle = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2
        emptyLabel.frame = NSRect(x: center.x - 80, y: center.y + ringMiddle - 17, width: 160, height: 34)
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
```

et remplacer `setItems(_:)` par :

```swift
    func setItems(_ items: [WheelItem], emptyMessage: String) {
        slotViews.forEach { $0.removeFromSuperview() }
        geometry = WheelGeometry(slotCount: items.count)
        slotViews = items.enumerated().map { index, item in
            let view = WheelSlotView(frame: bounds, item: item, index: index, geometry: geometry)
            addSubview(view, positioned: .below, relativeTo: centerView)
            return view
        }
        emptyLabel.stringValue = emptyMessage
        emptyLabel.isHidden = !items.isEmpty
        highlightedSlot = nil
    }
```

Dans `App/Wheel/WheelController.swift` : ajouter sous `private(set) var isDragInside = false` :

```swift
    /// Segments offered by a wheel for the dragged files.
    var segmentsProvider: (WheelMode, [URL]) -> [WheelSegment] = { _, _ in [] }
    /// Called after files were dropped on a segment, with its id.
    var onDrop: ((String, [URL]) -> Void)?
```

remplacer `load(_:)` et `reloadItems()` par :

```swift
    private func load(_ mode: WheelMode) {
        model = WheelModel(mode: mode, segments: segmentsProvider(mode, files))
        titleView.setMode(mode)
        reloadItems()
    }

    private func reloadItems() {
        setHoveredSlot(nil)
        guard let model else { return }
        wheelView.setItems(model.items, emptyMessage: model.mode.emptyMessage)
    }
```

et dans `dropTarget(_:didDropAt:)`, remplacer la fin (log + dismiss + return) par :

```swift
        let paths = files.map(\.path).joined(separator: ", ")
        AppInfo.gestureLog.notice("Drop on \(segment.id, privacy: .public): \(paths, privacy: .public)")
        let dropped = files
        dismiss(reason: "dropped on \(segment.id)")
        onDrop?(segment.id, dropped)
        return true
```

- [ ] **Step 5 : lancer les tests** — `scripts/test.sh` → `TESTS OK`. L'app compile, mais sa roue reste vide (« Aucune conversion… ») jusqu'à la tâche 6, qui branche le registre dans `GestureCoordinator` : c'est attendu.
- [ ] **Step 6 : build** — `scripts/build.sh Debug` → `BUILD OK`.
- [ ] **Step 7 : commit** — `git add -A && git commit -m "Phase 3: operation registry drives the wheel"`.

---

### Task 6 : Exécution, pastille HUD, journal, réglages et câblage

**Files :**
- Create : `App/Output/JobQueue.swift`, `App/Feedback/HUDToast.swift`, `App/Feedback/TechnicalLog.swift`
- Modify : `App/Settings/SettingsStore.swift`, `App/AppInfo.swift`, `App/GestureCoordinator.swift`, `App/AppDelegate.swift`

**Interfaces :**
- Consumes : `OperationRegistry`, `FileOperation`, `OperationContext`, `OutputLocator`, `OutputDestination`, `OperationError`, `WheelController.segmentsProvider/onDrop`.
- Produces : `JobQueue.run(_:inputs:)` ; `HUDController.begin(title:symbol:onCancel:) -> HUDToast`, `succeed(_:outputs:)`, `fail(_:message:)`, `cancel(_:)` ; `HUDToast.setProgress(_:)` ; `TechnicalLog.record(_:)`, `TechnicalLog.fileURL` ; `SettingsStore.outputDestination`, `.stripsLocation`, `.playsCompletionSound` ; `AppInfo.jobLog` ; `GestureCoordinator.performDebugLaunchArguments()`.

Cette tâche est de l'UI et de l'intégration : la vérification se fait par build + exécution réelle (`-debugRun`), pas par tests unitaires.

- [ ] **Step 1 : réglages et logger** — dans `App/AppInfo.swift`, après `gestureLog` :

```swift
    static let jobLog = Logger(subsystem: subsystem, category: "jobs")
```

`App/Settings/SettingsStore.swift` devient :

```swift
import Foundation

/// Typed access to UserDefaults. Keys live here and nowhere else.
enum SettingsStore {
    private enum Key {
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
        static let outputDestination = "outputDestination"
        static let customOutputFolder = "customOutputFolder"
        static let stripsLocation = "stripsLocation"
        static let playsCompletionSound = "playsCompletionSound"
    }

    /// Stored values of `Key.outputDestination`.
    private enum DestinationValue {
        static let besideOriginal = "besideOriginal"
        static let custom = "custom"
    }

    private static var defaults: UserDefaults { .standard }

    static var hasCompletedFirstLaunch: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstLaunch) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstLaunch) }
    }

    // Read-only until the Settings window can change them (phase 6).

    static var outputDestination: OutputDestination {
        switch defaults.string(forKey: Key.outputDestination) {
        case DestinationValue.besideOriginal:
            return .besideOriginal
        case DestinationValue.custom:
            guard let path = defaults.string(forKey: Key.customOutputFolder) else { return .convertedFolder }
            return .custom(URL(fileURLWithPath: path, isDirectory: true))
        default:
            return .convertedFolder
        }
    }

    /// "Retirer les données de localisation", off by default (§5.5).
    static var stripsLocation: Bool {
        defaults.bool(forKey: Key.stripsLocation)
    }

    /// Discreet sound when a job finishes, on by default (§5.6).
    static var playsCompletionSound: Bool {
        defaults.object(forKey: Key.playsCompletionSound) as? Bool ?? true
    }
}
```

- [ ] **Step 2 : journal technique** — `App/Feedback/TechnicalLog.swift` :

```swift
import Foundation

/// Technical failure details, in ~/Library/Logs/<App>/<App>.log (§5.6).
/// The HUD only ever shows the human message.
enum TechnicalLog {
    static var fileURL: URL {
        URL.libraryDirectory.appending(path: "Logs/\(AppInfo.name)/\(AppInfo.name).log")
    }

    static func record(_ message: String) {
        AppInfo.jobLog.error("\(message, privacy: .public)")
        let url = fileURL
        let line = "\(Date().ISO8601Format()) \(message)\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            AppInfo.jobLog.error("Cannot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 3 : pastille HUD** — `App/Feedback/HUDToast.swift` :

```swift
import AppKit

/// Pills stacked at the bottom-right of the screen reporting jobs (§5.6):
/// progress with a cancel button once a job runs over a second, then
/// "x créé" (click to reveal in Finder) or a human error message.
@MainActor
final class HUDController {
    static let progressDelay: TimeInterval = 1
    static let successDuration: TimeInterval = 3
    static let failureDuration: TimeInterval = 5
    private static let margin: CGFloat = 16
    private static let spacing: CGFloat = 8

    private var visible: [HUDToast] = []

    func begin(title: String, symbol: String, onCancel: @escaping () -> Void) -> HUDToast {
        let toast = HUDToast(onCancel: onCancel)
        toast.showProgress(title: title, symbol: symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.progressDelay) { [weak self] in
            guard let self, toast.isRunning else { return }
            self.present(toast)
        }
        return toast
    }

    func succeed(_ toast: HUDToast, outputs: [URL]) {
        toast.showSuccess(outputs: outputs)
        present(toast)
        remove(toast, after: Self.successDuration)
    }

    func fail(_ toast: HUDToast, message: String) {
        toast.showFailure(message: message)
        present(toast)
        remove(toast, after: Self.failureDuration)
    }

    func cancel(_ toast: HUDToast) {
        remove(toast, after: 0)
    }

    private func present(_ toast: HUDToast) {
        if !visible.contains(where: { $0 === toast }) {
            visible.append(toast)
        }
        layout()
        toast.panel.orderFrontRegardless()
    }

    private func remove(_ toast: HUDToast, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.visible.removeAll { $0 === toast }
            toast.close()
            self.layout()
        }
    }

    /// Stacks the pills upwards from the bottom-right corner of the screen under the cursor.
    private func layout() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        var y = frame.minY + Self.margin
        for toast in visible {
            toast.panel.setFrameOrigin(CGPoint(x: frame.maxX - HUDToast.size.width - Self.margin, y: y))
            y += HUDToast.size.height + Self.spacing
        }
    }
}

/// One pill: a non-activating panel, so it never steals focus.
@MainActor
final class HUDToast {
    static let size = NSSize(width: 300, height: 56)

    let panel: NSPanel
    private let content: HUDToastView
    private let onCancel: () -> Void
    private var outputs: [URL] = []
    private(set) var isRunning = true

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        content = HUDToastView(frame: NSRect(origin: .zero, size: Self.size))
        panel.contentView = content
        content.onClick = { [weak self] in self?.reveal() }
        content.onCancel = { [weak self] in self?.cancelTapped() }
    }

    func showProgress(title: String, symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        content.configure(icon: image, tint: .labelColor, text: "\(title)…", progress: 0)
    }

    func setProgress(_ fraction: Double) {
        guard isRunning else { return }
        content.setProgress(fraction)
    }

    func showSuccess(outputs: [URL]) {
        isRunning = false
        self.outputs = outputs
        let text = outputs.count == 1 ? "\(outputs[0].lastPathComponent) créé" : "\(outputs.count) fichiers créés"
        let icon = outputs.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
        content.configure(icon: icon, tint: nil, text: text, progress: nil)
    }

    func showFailure(message: String) {
        isRunning = false
        let icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: message)
        content.configure(icon: icon, tint: .systemOrange, text: message, progress: nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    private func reveal() {
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    private func cancelTapped() {
        guard isRunning else { return }
        isRunning = false
        onCancel()
    }
}

@MainActor
private final class HUDToastView: NSView {
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?

    private let material = NSVisualEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let cancelButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material.frame = bounds
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.masksToBounds = true
        addSubview(material)

        icon.frame = NSRect(x: 12, y: 12, width: 32, height: 32)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small
        bar.frame = NSRect(x: 54, y: 13, width: bounds.width - 54 - 44, height: 12)
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Annuler")
        cancelButton.isBordered = false
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.frame = NSRect(x: bounds.width - 36, y: 16, width: 24, height: 24)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        [icon, label, bar, cancelButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `progress` nil hides the bar and the cancel button.
    func configure(icon image: NSImage?, tint: NSColor?, text: String, progress: Double?) {
        icon.image = image
        icon.contentTintColor = tint
        label.stringValue = text
        let running = progress != nil
        bar.isHidden = !running
        cancelButton.isHidden = !running
        bar.doubleValue = progress ?? 0
        let textWidth = bounds.width - 54 - (running ? 44 : 14)
        label.frame = running
            ? NSRect(x: 54, y: 29, width: textWidth, height: 16)
            : NSRect(x: 54, y: 20, width: textWidth, height: 16)
    }

    func setProgress(_ fraction: Double) {
        bar.doubleValue = fraction
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    @objc private func cancelPressed() {
        onCancel?()
    }
}
```

- [ ] **Step 4 : file d'exécution** — `App/Output/JobQueue.swift` :

```swift
import AppKit

/// Runs operations off the main thread and reports through the HUD (§5.6).
/// New jobs never wait for running ones; the limit of two concurrent media
/// jobs arrives with ffmpeg in phase 4.
@MainActor
final class JobQueue {
    private static let completionSound = NSSound.Name("Pop")
    private static let genericFailure = "La conversion a échoué."

    private let hud = HUDController()
    private var running: [UUID: Task<Void, Never>] = [:]

    func run(_ operation: any FileOperation, inputs: [URL]) {
        let id = UUID()
        let context = OperationContext(output: OutputLocator(destination: SettingsStore.outputDestination),
                                       stripsLocation: SettingsStore.stripsLocation)
        let toast = hud.begin(title: operation.title, symbol: operation.symbol) { [weak self] in
            self?.running[id]?.cancel()
        }
        AppInfo.jobLog.info("Job \(operation.id, privacy: .public) started on \(inputs.count) file(s)")

        running[id] = Task.detached(priority: .userInitiated) {
            let result: Result<[URL], Error>
            do {
                result = .success(try await operation.run(inputs: inputs, context: context) { fraction in
                    Task { @MainActor in toast.setProgress(fraction) }
                })
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                self.finish(id, operation: operation, inputs: inputs, toast: toast, result: result)
            }
        }
    }

    private func finish(_ id: UUID, operation: any FileOperation, inputs: [URL], toast: HUDToast,
                        result: Result<[URL], Error>) {
        running[id] = nil
        switch result {
        case .success(let outputs):
            let paths = outputs.map(\.path).joined(separator: ", ")
            AppInfo.jobLog.info("Job \(operation.id, privacy: .public) done: \(paths, privacy: .public)")
            hud.succeed(toast, outputs: outputs)
            if SettingsStore.playsCompletionSound {
                NSSound(named: Self.completionSound)?.play()
            }
        case .failure(let error) where error is CancellationError:
            AppInfo.jobLog.info("Job \(operation.id, privacy: .public) cancelled")
            hud.cancel(toast)
        case .failure(let error):
            let paths = inputs.map(\.path).joined(separator: ", ")
            TechnicalLog.record("\(operation.id) failed on \(paths): \(String(reflecting: error))")
            hud.fail(toast, message: (error as? OperationError)?.message ?? Self.genericFailure)
        }
    }
}
```

- [ ] **Step 5 : câblage** — dans `App/GestureCoordinator.swift`, ajouter aux propriétés :

```swift
    private let registry = OperationRegistry.standard
    private let jobs = JobQueue()
```

au début de `start()` :

```swift
        wheel.segmentsProvider = { [registry] mode, files in
            registry.operations(for: files, kind: mode).map(\.segment)
        }
        wheel.onDrop = { [weak self] id, files in self?.runOperation(id, on: files) }
```

une méthode privée :

```swift
    private func runOperation(_ id: String, on files: [URL]) {
        guard let operation = registry.operation(withID: id) else {
            AppInfo.jobLog.error("Unknown operation \(id, privacy: .public)")
            return
        }
        jobs.run(operation, inputs: files)
    }
```

et remplacer le bloc `#if DEBUG … #endif` par :

```swift
#if DEBUG
extension GestureCoordinator {
    /// Development shortcuts, no drag needed:
    /// `open Pivot.app --args -debugWheel convert|tools|actions [-debugSlot N] [-debugSnapshot out.png]
    /// [-debugFiles '("/path/a", "/path/b")']` shows the wheel;
    /// `-debugRun convert.png -debugFiles '("/path/a")'` runs an operation as if dropped.
    func performDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: "debugFiles") ?? ["/System/Library/Desktop Pictures/", "/etc/hosts"]
        let files = paths.map { URL(fileURLWithPath: $0) }

        if let id = defaults.string(forKey: "debugRun") {
            runOperation(id, on: files)
        }
        guard let name = defaults.string(forKey: "debugWheel"),
              let mode = WheelMode.allCases.first(where: { "\($0)" == name }),
              let screen = NSScreen.main else { return }
        wheel.show(mode, files: files, at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        if defaults.object(forKey: "debugSlot") != nil {
            wheel.debugHighlight(slot: defaults.integer(forKey: "debugSlot"))
        }
        if let path = defaults.string(forKey: "debugSnapshot") {
            wheel.debugSnapshot(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
```

Dans `App/AppDelegate.swift`, `gestures.showDebugWheelIfRequested()` devient `gestures.performDebugLaunchArguments()`.

- [ ] **Step 6 : build + tests** — `scripts/build.sh Debug` → `BUILD OK` sans avertissement ; `scripts/test.sh` → `TESTS OK`.

- [ ] **Step 7 : exécution réelle** (le premier lancement écrivant dans Téléchargements peut afficher une invite macOS « accès au dossier Téléchargements » : prévenir Raphaël avant).

```bash
D=$(mktemp -d); sips -s format png /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns --out "$D/test pivot.png" >/dev/null
APP=build/Build/Products/Debug/Pivot.app
for op in convert.jpg convert.heic convert.pdf; do pkill -x Pivot; open -n -g "$APP" --args -debugRun $op -debugFiles "(\"$D/test pivot.png\")"; sleep 3; done
ls -la ~/Downloads/Convertis/ | grep "test pivot"
for f in ~/Downloads/Convertis/test\ pivot*; do sips -g format "$f" 2>/dev/null | tail -1; done
/usr/bin/log show --last 2m --info --predicate 'subsystem == "local.pivot.app" AND category == "jobs"' --style compact
```

Attendu : `test pivot.jpg`, `test pivot.heic`, `test pivot.pdf` présents, formats `jpeg` / `heic` (PDF : `file` → « PDF document »), lignes « Job … done » dans le log ; ensuite supprimer ces trois fichiers de test. Erreur : relancer avec un `.jpg` corrompu → ligne dans `~/Library/Logs/Pivot/Pivot.log` et « failed » dans le log.

- [ ] **Step 8 : commit** — `git add -A && git commit -m "Phase 3: job queue, HUD pill, technical log, wiring"`.

---

### Task 7 : Vérification finale et documentation

**Files :** Modify : `CLAUDE.md`

- [ ] **Step 1 : vérification** (superpowers:verification-before-completion) — `scripts/test.sh` (compter les tests, 0 échec), `scripts/build.sh Debug` (OK, signé « Pivot Dev »), relecture de la checklist « Contraintes globales » ligne par ligne contre le code.
- [ ] **Step 2 : invites de confidentialité** — avec `-debugRun` sur un fichier du Bureau, lister les requêtes `tccd` du processus (`log show --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS "pid=<PID>"'`) et noter lesquelles apparaissent (attendu : Bureau en lecture puisque `-debugRun` n'est pas un vrai drop ; le vrai drop doit être vérifié à la main par Raphaël).
- [ ] **Step 3 : CLAUDE.md** — ligne de phase 2 → ✅ (validée par Raphaël), ligne de phase 3 → 🟡 avec l'état réel ; ajouter `-debugRun` à la ligne « Debug sans drag ».
- [ ] **Step 4 : commit + push** — `git add -A && git commit -m "Phase 3: status and docs" && git push`.
- [ ] **Step 5 : résumé à Raphaël** en français, avec la checklist manuelle : drag depuis le Finder et le Bureau d'une image → chaque format, plusieurs images → PDF, PDF une page / plusieurs pages, HEIC iPhone tourné, PNG transparent → JPG, fichier sans conversion (roue vide avec message), dossier, collision de nom (convertir deux fois), clic sur la pastille → Finder, conversion longue (PDF de 100 pages) → barre + annulation, absence d'invite « Bureau » après un vrai drop, original intact.
