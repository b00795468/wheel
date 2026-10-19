# Phase 5 — Outils (Compresser, Redimensionner) et Actions — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Ce projet impose `superpowers:executing-plans` (voir CLAUDE.md, section Skills).

**Goal :** la roue ⌘ « Outils » compresse (images, PDF, vidéos) et redimensionne (sous-roue 50 % / 1920 / 1280 / 800 px) ; la roue ⌃ « Actions » copie le chemin, révèle dans le Finder et envoie par AirDrop — dossiers compris.

**Architecture :** le modèle de roue gagne des sous-roues : un `WheelSegment` peut avoir des enfants, qui s'ouvrent au survol prolongé (500 ms, comme « Plus… ») avec un segment « Retour ». Le registre regroupe les opérations portant le même `OperationGroup` derrière un segment parent. Les outils gardent le format d'origine (`ImageRewriter` : ImageIO, ou ffmpeg pour WebP) et ajoutent un suffixe au nom ; un résultat compressé qui n'est pas plus petit est refusé. Les actions s'exécutent sur le thread principal et choisissent leur propre message de pastille (`completionMessage`).

**Tech stack :** Swift 5, AppKit (NSPasteboard, NSWorkspace, NSSharingService), ImageIO, PDFKit, ffmpeg embarqué (hevc/h264_videotoolbox), XCTest.

**Spec :** `SPEC.md` (§5.1 dossiers, §5.2 roue, §5.4 Outils et Actions, §5.6, §9 phase 5).

## Contraintes globales

- **Compresser** : images (JPG qualité 75 %, PNG → optimisation sans perte si possible), vidéo (H.264/HEVC VideoToolbox, ~1080p, débit raisonnable), PDF (`PDFDocument` réécrit avec images downsamplées). Le nom de sortie prend le suffixe ` (compressé)` (§5.4).
- Écart mesuré pendant l'exécution : les options d'écriture PDFKit (`saveImagesAsJPEG`, `optimizeImagesForScreen`) n'ont aucun effet sur ce macOS ; le PDF passe par le filtre système « Reduce File Size » (celui d'Aperçu), qui conserve texte et vecteurs mais pas les liens ni les annotations.
- **Redimensionner** (images, vidéo) : sous-roue avec préréglages **50 %**, **1920 px**, **1280 px**, **800 px** (plus grand côté, ratio conservé) (§5.4).
- **Copier le chemin** (chemin POSIX, plusieurs fichiers séparés par des retours à la ligne) ; **Afficher dans le Finder** ; **AirDrop** (`NSSharingService(named: .sendViaAirDrop)`) (§5.4).
- Dossiers : uniquement les actions (§5.2).
- Au-delà de 6–8 segments, pagination ; survol prolongé 500 ms pour naviguer (§5.2).
- Jamais d'écrasement, jamais de modification de l'original ; écriture temporaire puis déplacement atomique (§5.5).
- Erreurs en français humain ; détail technique dans le log (§5.6).
- Ne jamais lire le fichier avant le drop : les segments se décident sur l'URL seule.
- Interface en français ; code et commentaires en anglais ; zéro package externe.

Décisions prises dans ce plan (à signaler dans le résumé) :
- Les outils **gardent le format** du fichier ; la vidéo compressée sort en HEVC (`.mov` si l'original est un MOV, sinon `.mp4`), la vidéo redimensionnée en H.264.
- **Jamais d'agrandissement** : un préréglage plus grand que le fichier donne « Ce fichier fait déjà moins de 1920 px. ».
- Un fichier compressé **qui n'est pas plus petit** n'est pas livré : « Ce fichier est déjà compressé au mieux. » (cas typique : PNG déjà optimisé).
- BMP n'est pas proposé dans « Compresser » (format sans compression utile) ; il l'est dans « Redimensionner ».

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `App/Wheel/WheelModel.swift` | `WheelSegment.children`, `WheelItem.back`, sous-roue (`open`, `goBack`, `title`) |
| `App/Operations/FileOperation.swift` | `OperationGroup`, `group`, `completionMessage`, erreurs d'outils/actions |
| `App/Operations/OperationRegistry.swift` | `segments(for:kind:)` (regroupement), nouvelles opérations |
| `App/Operations/Converters/ImageFormat.swift` | AVIF, BMP, `matching(_:)`, `withQuality(_:)` |
| `App/Operations/Converters/ImageConverter.swift` | `downscaledImage(from:maxPixelSize:)` |
| `App/Operations/Engines/WebPEncoder.swift` (nouveau) | Encodage WebP via ffmpeg (partagé) |
| `App/Operations/Engines/FFmpegRunner.swift` | `MediaProbe.width/height` |
| `App/Operations/Converters/ImageToWebPOperation.swift` | Utilise `WebPEncoder` |
| `App/Operations/Tools/ImageRewriter.swift` (nouveau) | Réécrire une image dans le format de son fichier |
| `App/Operations/Tools/VideoScaling.swift` (nouveau) | Filtres ffmpeg sans agrandissement, dimensions paires |
| `App/Operations/Tools/CompressOperation.swift` (nouveau) | « Compresser » |
| `App/Operations/Tools/ResizeOperation.swift` (nouveau) | `ResizePreset` + « Redimensionner » |
| `App/Operations/Actions/CopyPathAction.swift`, `RevealAction.swift`, `AirDropAction.swift` (nouveaux) | Actions |
| `App/Wheel/WheelView.swift`, `App/Wheel/WheelController.swift`, `App/GestureCoordinator.swift` | Sous-roue à l'écran |
| `App/Feedback/HUDToast.swift`, `App/Output/JobQueue.swift` | Message de pastille choisi par l'opération |
| `Tests/…` | Modèle, regroupement, outils, actions |

---

### Task 1 : sous-roues dans le modèle et regroupement dans le registre

**Files :**
- Modify : `App/Wheel/WheelModel.swift`, `App/Operations/FileOperation.swift`, `App/Operations/OperationRegistry.swift`
- Modify : `Tests/GestureTests/WheelModelTests.swift`, `Tests/GestureTests/WheelViewTests.swift`
- Create : `Tests/OperationTests/RegistryGroupingTests.swift`

**Interfaces :**
- Produces : `WheelSegment(id:title:symbol:children:)` (`children` défaut `[]`) ; `WheelItem.back`, `WheelItem.backTitle`, `WheelItem.backSymbol` ; `WheelModel.parent`, `title`, `open(_:)`, `goBack()` ; `struct OperationGroup(id:title:symbol:)` ; `FileOperation.group` (défaut `nil`) ; `OperationRegistry.segments(for:kind:) -> [WheelSegment]`.

- [ ] **Step 1 : tests** — ajouter à `WheelModelTests` :

```swift
    private func parent(children count: Int) -> WheelSegment {
        WheelSegment(id: "group", title: "Redimensionner", symbol: "aspectratio", children: segments(count))
    }

    func testOpeningAGroupShowsItsChildrenAndBack() {
        var model = WheelModel(mode: .tools, segments: [WheelSegment(id: "c", title: "C", symbol: "circle"), parent(children: 4)])
        XCTAssertEqual(model.title, "Outils")

        model.open(parent(children: 4))

        XCTAssertEqual(model.title, "Redimensionner")
        XCTAssertEqual(ids(model.items), ["s0", "s1", "s2", "s3", "back"])
        model.goBack()
        XCTAssertEqual(ids(model.items), ["c", "group"])
        XCTAssertEqual(model.title, "Outils")
    }

    func testALeafSegmentDoesNotOpen() {
        var model = WheelModel(mode: .tools, segments: segments(2))
        model.open(segments(1)[0])
        XCTAssertNil(model.parent)
    }

    func testABigSubWheelPagesAndKeepsBack() {
        var model = WheelModel(mode: .tools, segments: [parent(children: 10)])
        model.open(parent(children: 10))

        XCTAssertEqual(ids(model.items), ["s0", "s1", "s2", "s3", "s4", "s5", "more", "back"])
        model.nextPage()
        XCTAssertEqual(ids(model.items), ["s6", "s7", "s8", "s9", "more", "back"])
    }
```

et dans son helper `ids(_:)`, ajouter le cas `case .back: "back"` au `switch`.

Dans `Tests/GestureTests/WheelViewTests.swift`, la ligne `for items in [segments.map(WheelItem.segment) + [.more], []] {` devient `for items in [segments.map(WheelItem.segment) + [.more, .back], []] {`.

`Tests/OperationTests/RegistryGroupingTests.swift` :

```swift
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
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `extra argument 'children'`, `type 'WheelItem' has no member 'back'`…

- [ ] **Step 3 : implémenter** — dans `App/Wheel/WheelModel.swift`, remplacer tout depuis `/// One choice on the wheel.` jusqu'à la fin du fichier par :

```swift
/// One choice on the wheel. A segment with children opens them as a
/// sub-wheel when hovered, instead of accepting the drop (§5.4).
struct WheelSegment: Equatable {
    let id: String
    let title: String
    let symbol: String
    var children: [WheelSegment] = []
}

/// What a slot of the ring shows: a segment, the "more" pager, or the way
/// back from a sub-wheel.
enum WheelItem: Equatable {
    case segment(WheelSegment)
    case more
    case back

    static let moreTitle = "Plus…"
    static let moreSymbol = "ellipsis"
    static let backTitle = "Retour"
    static let backSymbol = "chevron.backward"
}

/// Segments of the current wheel or sub-wheel, split into pages of at
/// most `maxItemsPerPage` slots. A sub-wheel always ends with `.back`;
/// when paging is needed, `.more` cycles to the next page.
struct WheelModel: Equatable {
    static let maxItemsPerPage = 8

    let mode: WheelMode
    let segments: [WheelSegment]
    private(set) var page = 0
    /// The segment whose sub-wheel is shown, nil on the main wheel.
    private(set) var parent: WheelSegment?

    init(mode: WheelMode, segments: [WheelSegment]) {
        self.mode = mode
        self.segments = segments
    }

    var title: String { parent?.title ?? mode.title }

    private var current: [WheelSegment] { parent?.children ?? segments }
    /// Slots taken by navigation: "Retour" in a sub-wheel.
    private var reservedSlots: Int { parent == nil ? 0 : 1 }
    private var needsPaging: Bool { current.count > Self.maxItemsPerPage - reservedSlots }
    private var segmentsPerPage: Int { Self.maxItemsPerPage - reservedSlots - (needsPaging ? 1 : 0) }

    var pageCount: Int { max(1, (current.count + segmentsPerPage - 1) / segmentsPerPage) }

    var items: [WheelItem] {
        let start = page * segmentsPerPage
        let end = min(start + segmentsPerPage, current.count)
        var items = current[start..<end].map(WheelItem.segment)
        if needsPaging { items.append(.more) }
        if parent != nil { items.append(.back) }
        return items
    }

    mutating func nextPage() {
        page = (page + 1) % pageCount
    }

    /// Shows the children of `segment` in place of the main wheel.
    mutating func open(_ segment: WheelSegment) {
        guard !segment.children.isEmpty else { return }
        parent = segment
        page = 0
    }

    mutating func goBack() {
        parent = nil
        page = 0
    }
}
```

Dans `App/Operations/FileOperation.swift`, ajouter avant `protocol FileOperation` :

```swift
/// Operations shown together behind one segment that opens a sub-wheel.
struct OperationGroup: Equatable, Sendable {
    let id: String
    let title: String
    let symbol: String
}
```

dans le protocole, après `var usesMediaEngine: Bool { get }` :

```swift
    /// Groups this operation with others behind a sub-wheel segment.
    var group: OperationGroup? { get }
```

et dans l'extension, après `var usesMediaEngine: Bool { false }` :

```swift
    var group: OperationGroup? { nil }
```

Dans `App/Operations/OperationRegistry.swift`, ajouter avant `func operation(withID:)` :

```swift
    /// Wheel segments for `files`, in registry order: operations sharing a
    /// group become one segment whose children open as a sub-wheel.
    func segments(for files: [URL], kind: WheelMode) -> [WheelSegment] {
        var segments: [WheelSegment] = []
        for operation in operations(for: files, kind: kind) {
            guard let group = operation.group else {
                segments.append(operation.segment)
                continue
            }
            if let index = segments.firstIndex(where: { $0.id == group.id }) {
                segments[index].children.append(operation.segment)
            } else {
                segments.append(WheelSegment(id: group.id, title: group.title, symbol: group.symbol,
                                             children: [operation.segment]))
            }
        }
        return segments
    }
```

Dans `App/Wheel/WheelView.swift`, dans `WheelSlotView.init`, le `switch item` reçoit le cas :

```swift
        case .back: (WheelItem.backTitle, WheelItem.backSymbol)
```

- [ ] **Step 4 : lancer les tests** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK`.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 5: sub-wheels in the wheel model, grouped segments"`.

---

### Task 2 : « Compresser » (images, PDF, vidéo)

**Files :**
- Create : `App/Operations/Engines/WebPEncoder.swift`, `App/Operations/Tools/ImageRewriter.swift`, `App/Operations/Tools/VideoScaling.swift`, `App/Operations/Tools/CompressOperation.swift`, `Tests/OperationTests/CompressOperationTests.swift`
- Modify : `App/Operations/Converters/ImageFormat.swift`, `App/Operations/Converters/ImageToWebPOperation.swift`, `App/Operations/Engines/FFmpegRunner.swift`, `App/Operations/FileOperation.swift`, `App/Operations/OperationRegistry.swift`, `Tests/Support/Fixtures.swift`, `Tests/OperationTests/FFmpegRunnerTests.swift`, `Tests/OperationTests/OperationRegistryTests.swift`

**Interfaces :**
- Produces : `ImageFormat.avif`, `.bmp`, `ImageFormat.matching(_:) -> ImageFormat?`, `withQuality(_:)` ; `WebPEncoder.encode(_:quality:to:with:) async throws` ; `ImageRewriter.canRewrite(_:)`, `ImageRewriter.write(_:like:to:quality:properties:ffmpeg:) async throws` ; `VideoScaling.fitting(longSide:)`, `VideoScaling.half` ; `MediaProbe.width`, `.height` ; `CompressOperation` (`suffix`, `imageQuality`, `isCompressibleImage(_:)`) ; `OperationError.alreadyCompressed`, `OperationError.alreadySmall(than:)`, `OperationError.airDropUnavailable` ; fixtures `Fixtures.makeNoiseImage`, `writeNoiseImage`, `writeImagePDF`, `writeVideo(…quality:)`.

- [ ] **Step 1 : fixtures** — dans `Tests/Support/Fixtures.swift` :
  - signature de `writeVideo` : ajouter le paramètre `quality: String? = nil` après `size:`, et remplacer `arguments += ["-c:v", codec, "-pix_fmt", "yuv420p", "-shortest", url.path]` par :

```swift
        arguments += ["-c:v", codec, "-pix_fmt", "yuv420p"]
        if let quality { arguments += ["-q:v", quality] }
        arguments += ["-shortest", url.path]
```

  - ajouter dans `enum Fixtures` :

```swift
    /// Random pixels: compresses badly losslessly, well lossily.
    static func makeNoiseImage(width: Int, height: Int) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = .random(in: 0...255)
            pixels[index + 1] = .random(in: 0...255)
            pixels[index + 2] = .random(in: 0...255)
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
    }

    @discardableResult
    static func writeNoiseImage(_ name: String, in directory: URL, type: UTType, width: Int = 400, height: Int = 300,
                                quality: Double = 1) throws -> URL {
        let url = directory.appending(path: name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, makeNoiseImage(width: width, height: height),
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// One-page PDF embedding a large noise image (stored losslessly by Core Graphics).
    @discardableResult
    static func writeImagePDF(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPage(mediaBox: &box)
        context.draw(makeNoiseImage(width: 1600, height: 1200), in: box)
        context.endPage()
        context.closePDF()
        return url
    }
```

- [ ] **Step 2 : tests** — `Tests/OperationTests/CompressOperationTests.swift` :

```swift
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

final class CompressOperationTests: XCTestCase {
    private func context(_ dir: URL, ffmpeg: Bool = true) throws -> OperationContext {
        OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))), stripsLocation: false,
                         ffmpeg: ffmpeg ? try Fixtures.ffmpeg() : nil)
    }

    private func compress(_ input: URL, in dir: URL) async throws -> URL {
        let outputs = try await CompressOperation().run(inputs: [input], context: try context(dir)) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    func testJPEGIsReencodedSmallerWithTheSuffix() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeNoiseImage("photo.jpg", in: dir, type: .jpeg)

        let output = try await compress(input, in: dir)

        XCTAssertEqual(output.lastPathComponent, "photo (compressé).jpg")
        XCTAssertLessThan(try size(output), try size(input))
        let info = try Fixtures.info(output)
        XCTAssertEqual(info.type, UTType.jpeg.identifier)
        XCTAssertEqual([info.width, info.height], [400, 300])
    }

    func testHEICAndWebPKeepTheirFormat() async throws {
        let dir = try Fixtures.directory(for: self)
        let heic = try Fixtures.writeNoiseImage("a.heic", in: dir, type: .heic)
        let webp = dir.appending(path: "b.webp")
        try await WebPEncoder.encode(Fixtures.makeNoiseImage(width: 400, height: 300), quality: 100, to: webp,
                                     with: try Fixtures.ffmpeg())

        let compressedHEIC = try await compress(heic, in: dir)
        let compressedWebP = try await compress(webp, in: dir)

        XCTAssertEqual(try Fixtures.info(compressedHEIC).type, UTType.heic.identifier)
        XCTAssertEqual(try Fixtures.info(compressedWebP).type, UTType.webP.identifier)
        XCTAssertLessThan(try size(compressedWebP), try size(webp))
    }

    func testTIFFGetsLosslessLZW() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("scan.tiff", in: dir, type: .tiff, width: 400, height: 300)

        let output = try await compress(input, in: dir)

        XCTAssertLessThan(try size(output), try size(input))
        let tiff = try Fixtures.info(output).properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFCompression] as? Int, 5)
    }

    func testAFileThatWouldNotShrinkIsRefusedAndNothingIsWritten() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeNoiseImage("noise.png", in: dir, type: .png)

        do {
            _ = try await compress(input, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .alreadyCompressed)
        }
        let out = dir.appending(path: "out")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? [], [])
    }

    func testPDFImagesAreDownsampled() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImagePDF("scan.pdf", in: dir)

        let output = try await compress(input, in: dir)

        XCTAssertEqual(output.lastPathComponent, "scan (compressé).pdf")
        XCTAssertLessThan(try size(output), try size(input))
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
        XCTAssertEqual(PDFDocument(url: output)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 400, height: 300))
    }

    func testVideoBecomesHEVCAtMost1080p() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir, seconds: 2, size: "3840x2160", quality: "80")

        let output = try await compress(input, in: dir)

        XCTAssertEqual(output.lastPathComponent, "clip (compressé).mp4")
        XCTAssertLessThan(try size(output), try size(input))
        XCTAssertEqual(try Fixtures.codecs(of: output), ["hevc", "aac"])
        let probe = try await Fixtures.ffmpeg().probe(output)
        XCTAssertEqual(probe.width, 1920)
        XCTAssertEqual(probe.height, 1080)
    }

    func testAcceptedTypes() {
        let operation = CompressOperation()
        func type(_ ext: String) -> UTType { UTType(filenameExtension: ext)! }
        for ext in ["jpg", "png", "heic", "tiff", "webp", "avif", "pdf", "mov", "mkv"] {
            XCTAssertTrue(operation.accepts([type(ext)]), ext)
        }
        for ext in ["bmp", "mp3", "wav", "txt"] {
            XCTAssertFalse(operation.accepts([type(ext)]), ext)
        }
        XCTAssertFalse(operation.accepts([.folder]))
    }
}
```

Ajouter à `FFmpegRunnerTests` :

```swift
    func testProbeReportsTheVideoSize() throws {
        let json = #"{"streams":[{"codec_name":"hevc","codec_type":"video","width":3840,"height":2160,"disposition":{"attached_pic":0}}],"format":{"duration":"1.0"}}"#
        let probe = try MediaProbe.parse(Data(json.utf8))
        XCTAssertEqual(probe.width, 3840)
        XCTAssertEqual(probe.height, 2160)
    }
```

Dans `OperationRegistryTests`, remplacer `testToolsAndActionsArriveInPhase5` par :

```swift
    func testCompressIsOfferedForCompressibleFiles() {
        XCTAssertEqual(ids(["a.pdf"], .tools), ["tool.compress"])
        XCTAssertTrue(ids(["a.png"], .tools).contains("tool.compress"))
        XCTAssertFalse(ids(["a.bmp"], .tools).contains("tool.compress"))
        XCTAssertEqual(ids(["a.mp3"], .tools), [])
        XCTAssertEqual(ids(["Vacances/"], .tools), [])
    }
```

- [ ] **Step 3 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'CompressOperation' in scope`, `WebPEncoder`…

- [ ] **Step 4 : implémenter** — `App/Operations/Converters/ImageFormat.swift`, après `static let tiff = …` :

```swift
    static let avif = ImageFormat(type: FileTypes.avif, fileExtension: "avif", title: "AVIF", symbol: "photo",
                                  supportsAlpha: true, lossyQuality: 0.9, sameFormatTypes: [FileTypes.avif])
    static let bmp = ImageFormat(type: .bmp, fileExtension: "bmp", title: "BMP", symbol: "photo",
                                 supportsAlpha: false, lossyQuality: nil, sameFormatTypes: [.bmp])

    /// The ImageIO format of a file of `type`, to write it back as it was.
    static func matching(_ type: UTType) -> ImageFormat? {
        [jpeg, png, heic, tiff, avif, bmp].first { $0.isSameFormat(as: type) }
    }

    /// Same format with another lossy quality; lossless formats are unchanged.
    func withQuality(_ quality: Double) -> ImageFormat {
        ImageFormat(type: type, fileExtension: fileExtension, title: title, symbol: symbol, supportsAlpha: supportsAlpha,
                    lossyQuality: lossyQuality == nil ? nil : quality, sameFormatTypes: sameFormatTypes)
    }
```

`App/Operations/Engines/WebPEncoder.swift` :

```swift
import CoreGraphics
import Foundation

/// WebP through the embedded ffmpeg's libwebp, since ImageIO cannot encode
/// it: the image goes through a temporary PNG. Metadata is not carried over.
enum WebPEncoder {
    static func encode(_ image: CGImage, quality: Int, to url: URL, with ffmpeg: FFmpegRunner) async throws {
        let png = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        try ImageConverter.write(image, as: .png, to: png)
        do {
            try await ffmpeg.convert(["-i", png.path, "-c:v", "libwebp", "-quality", String(quality), url.path],
                                     duration: nil) { _ in }
        } catch let error as FFmpegError {
            throw OperationError.writeFailed.withDetail(error.description)
        }
    }
}
```

`App/Operations/Converters/ImageToWebPOperation.swift` : `static let quality = "90"` devient `static let quality = 90`, et le corps de la boucle, après le `guard … uprightImage`, devient :

```swift
            outputs.append(try await context.output.commitAsync(baseName: input.baseName, fileExtension: "webp",
                                                                for: input) { temporary in
                try await WebPEncoder.encode(image, quality: Self.quality, to: temporary, with: ffmpeg)
            })
            progress(Double(index + 1) / Double(inputs.count))
```

(le PNG temporaire et le `do/catch FFmpegError` disparaissent de ce fichier ; le commentaire de type devient `/// "WebP": images to WebP through the embedded ffmpeg (§3), see WebPEncoder.`).

`App/Operations/Tools/ImageRewriter.swift` :

```swift
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Writes an image back in the format of the file it came from, since the
/// tools keep formats: ImageIO for most, the embedded ffmpeg for WebP.
enum ImageRewriter {
    static func canRewrite(_ type: UTType) -> Bool {
        type.conforms(to: .webP) || ImageFormat.matching(type) != nil
    }

    /// `quality` applies to lossy formats only (nil: the format's default).
    static func write(_ image: CGImage, like type: UTType, to url: URL, quality: Double?,
                      properties: [CFString: Any], ffmpeg: FFmpegRunner?) async throws {
        if type.conforms(to: .webP) {
            guard let ffmpeg else { throw OperationError.engineMissing }
            let percent = Int(((quality ?? 0.9) * 100).rounded())
            try await WebPEncoder.encode(image, quality: percent, to: url, with: ffmpeg)
            return
        }
        guard var format = ImageFormat.matching(type) else { throw OperationError.unreadableImage }
        if let quality { format = format.withQuality(quality) }
        try ImageConverter.write(image, as: format, to: url, properties: properties)
    }
}
```

`App/Operations/Tools/VideoScaling.swift` :

```swift
import Foundation

/// ffmpeg scale filters that never enlarge and keep even sizes, which
/// H.264 and HEVC require.
enum VideoScaling {
    /// Longer side at most `longSide`, aspect ratio kept.
    static func fitting(longSide: Int) -> String {
        "scale='if(gte(iw,ih),min(\(longSide),trunc(iw/2)*2),-2)':'if(gte(iw,ih),-2,min(\(longSide),trunc(ih/2)*2))'"
    }

    static let half = "scale=trunc(iw/4)*2:trunc(ih/4)*2"
}
```

Dans `App/Operations/Engines/FFmpegRunner.swift` :
  - `MediaProbe` : après `var audioCodec: String?`, ajouter `var width: Int? = nil` et `var height: Int? = nil` (avec le commentaire `/// Coded size of that video stream.` au-dessus de `width`) ;
  - dans `parse`, `struct Stream` reçoit `let width: Int?` et `let height: Int?`, et la fin de `parse` devient :

```swift
        let video = streams.first { $0.codecType == "video" && $0.disposition?["attached_pic"] != 1 }
        let audio = streams.first { $0.codecType == "audio" }
        let duration = output.format?.duration.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        return MediaProbe(duration: duration, videoCodec: video?.codecName, audioCodec: audio?.codecName,
                          width: video?.width, height: video?.height)
```

(la fonction locale `firstCodec` disparaît) ;
  - dans `probe(_:)`, `"format=duration:stream=codec_type,codec_name:stream_disposition=attached_pic"` devient `"format=duration:stream=codec_type,codec_name,width,height:stream_disposition=attached_pic"`, et le commentaire de `parse` est mis à jour de même.

Dans `App/Operations/FileOperation.swift`, à la fin de `OperationError` :

```swift
    static let alreadyCompressed = OperationError(message: "Ce fichier est déjà compressé au mieux.")
    static let airDropUnavailable = OperationError(message: "AirDrop n'est pas disponible. Vérifiez qu'il est activé.")

    static func alreadySmall(than limit: String) -> OperationError {
        OperationError(message: "Ce fichier fait déjà moins de \(limit).")
    }
```

`App/Operations/Tools/CompressOperation.swift` :

```swift
import Foundation
import ImageIO
import Quartz
import UniformTypeIdentifiers

/// "Compresser" (§5.4): images re-encoded at 75 % (PNG and TIFF without
/// loss), PDFs through the system "Reduce File Size" filter, videos
/// re-encoded in HEVC at most 1080p. The format is kept, and a result that
/// is not smaller is refused instead of being handed over.
struct CompressOperation: FileOperation {
    static let suffix = " (compressé)"
    static let imageQuality = 0.75
    static let videoMaxLongSide = 1920
    /// TIFF compression tag value for LZW (lossless).
    private static let tiffLZW = 5

    let id = "tool.compress"
    let kind = WheelMode.tools
    let title = "Compresser"
    let symbol = "arrow.down.right.and.arrow.up.left"
    var usesMediaEngine: Bool { true }

    /// BMP is left out: re-encoding it gains nothing.
    static func isCompressibleImage(_ type: UTType) -> Bool {
        type.conforms(to: .webP) || ImageFormat.matching(type).map { $0 != .bmp } ?? false
    }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy {
            Self.isCompressibleImage($0) || FileTypes.isPDF($0) || FileTypes.isVideo($0)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { progress((Double(index) + $0) / Double(inputs.count)) }
            let type = FileTypes.type(of: input)
            let baseName = input.baseName + Self.suffix
            if FileTypes.isVideo(type) {
                outputs.append(try await compressVideo(input, baseName: baseName, context: context, progress: share))
            } else {
                outputs.append(try await context.output.commitAsync(baseName: baseName,
                                                                    fileExtension: input.pathExtension.lowercased(),
                                                                    for: input) { temporary in
                    if FileTypes.isPDF(type) {
                        try Self.compressPDF(input, to: temporary)
                    } else {
                        try await Self.compressImage(input, type: type, to: temporary, context: context)
                    }
                    try Self.requireSmaller(temporary, than: input)
                })
            }
            share(1)
        }
        return outputs
    }

    private static func compressImage(_ input: URL, type: UTType, to url: URL, context: OperationContext) async throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = ImageConverter.uprightImage(from: source) else {
            throw OperationError.unreadableImage
        }
        var properties = ImageConverter.metadata(of: source, stripsLocation: context.stripsLocation)
        if type.conforms(to: .tiff) {
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = tiffLZW
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        try await ImageRewriter.write(image, like: type, to: url, quality: imageQuality, properties: properties,
                                      ffmpeg: context.ffmpeg)
    }

    /// The system filter behind Preview's "Reduce File Size": images are
    /// downsampled and JPEG-compressed, text and vectors are kept. (PDFKit's
    /// saveImagesAsJPEG / optimizeImagesForScreen write options were measured
    /// to have no effect.) Links and annotations are not carried over.
    private static let reduceFileSizeFilter = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")

    private static func compressPDF(_ input: URL, to url: URL) throws {
        // Reports locked or unreadable PDFs with a human message.
        _ = try PDFConverter.openDocument(input)
        guard let document = CGPDFDocument(input as CFURL),
              let filter = QuartzFilter(url: reduceFileSizeFilter),
              let context = CGContext(url as CFURL, mediaBox: nil, nil),
              filter.apply(to: context) else {
            throw OperationError.writeFailed
        }
        defer { context.closePDF() }
        for index in 1...document.numberOfPages {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw OperationError.unreadablePDF }
            // Redraw upright: the page's /Rotate is applied by the drawing transform.
            let crop = page.getBoxRect(.cropBox)
            let quarterTurn = (page.rotationAngle / 90) % 2 != 0
            var box = CGRect(x: 0, y: 0, width: quarterTurn ? crop.height : crop.width,
                             height: quarterTurn ? crop.width : crop.height)
            context.beginPage(mediaBox: &box)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: box, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.endPage()
        }
    }

    /// HEVC bitrate for the output's longer side: sensible for 1080p and below.
    static func videoBitrate(for probe: MediaProbe) -> String {
        let longSide = min(max(probe.width ?? videoMaxLongSide, probe.height ?? 0), videoMaxLongSide)
        switch longSide {
        case 1600...: return "4M"
        case 1000...: return "2500k"
        default: return "1500k"
        }
    }

    private func compressVideo(_ input: URL, baseName: String, context: OperationContext,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        let probe: MediaProbe
        do {
            probe = try await ffmpeg.probe(input)
        } catch let error as FFmpegError {
            throw OperationError.unreadableVideo.withDetail(error.description)
        }
        guard probe.videoCodec != nil else { throw OperationError.noVideo }
        let isMOV = FileTypes.type(of: input).conforms(to: .quickTimeMovie)

        return try await context.output.commitAsync(baseName: baseName, fileExtension: isMOV ? "mov" : "mp4",
                                                    for: input) { temporary in
            var arguments = ["-i", input.path, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn",
                             "-vf", VideoScaling.fitting(longSide: Self.videoMaxLongSide),
                             "-c:v", "hevc_videotoolbox", "-b:v", Self.videoBitrate(for: probe),
                             "-tag:v", "hvc1", "-c:a", "aac_at", "-b:a", "128k"]
            if !isMOV { arguments += ["-movflags", "+faststart"] }
            do {
                try await ffmpeg.convert(arguments + [temporary.path], duration: probe.duration, progress: progress)
            } catch let error as FFmpegError {
                throw OperationError.unreadableVideo.withDetail(error.description)
            }
            try Self.requireSmaller(temporary, than: input)
        }
    }

    private static func requireSmaller(_ output: URL, than input: URL) throws {
        func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        guard size(output) < size(input) else { throw OperationError.alreadyCompressed }
    }
}
```

`App/Operations/OperationRegistry.swift` : remplacer `static let standard = …` (toute l'expression) par :

```swift
    static let standard: OperationRegistry = {
        var operations: [any FileOperation] = [
            ConvertToImageOperation(format: .jpeg, acceptsPDF: true),
            ConvertToImageOperation(format: .png, acceptsPDF: true),
            ConvertToImageOperation(format: .heic, acceptsPDF: false),
            ImageToWebPOperation(),
            ConvertToImageOperation(format: .tiff, acceptsPDF: false),
            ImagesToPDFOperation(),
        ]
        operations += MediaOutput.allCases.map { MediaConvertOperation(output: $0) as any FileOperation }
        operations.append(CompressOperation())
        return OperationRegistry(operations: operations)
    }()
```

- [ ] **Step 5 : lancer les tests** — `scripts/test.sh` → `TESTS OK`. Si le test PDF ne rétrécit pas, vérifier d'abord (systematic-debugging) quelles options `PDFDocumentWriteOption` sont prises en compte avant de changer d'approche ; si aucune ne réduit la taille, le signaler à Raphaël (la SPEC prévoit un report en v2).
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 5: Compresser for images, PDFs and videos"`.

---

### Task 3 : « Redimensionner » (images et vidéos, 4 préréglages)

**Files :**
- Create : `App/Operations/Tools/ResizeOperation.swift`, `Tests/OperationTests/ResizeOperationTests.swift`
- Modify : `App/Operations/Converters/ImageConverter.swift`, `App/Operations/OperationRegistry.swift`, `Tests/OperationTests/OperationRegistryTests.swift`

**Interfaces :**
- Consumes : `ImageRewriter`, `VideoScaling`, `MediaProbe.width/height`, `OperationError.alreadySmall(than:)`, `OperationGroup`, `MediaOutput.videoQuality`.
- Produces : `enum ResizePreset { half, long1920, long1280, long800 }` (`id`, `title`, `maxLongSide`, `targetLongSide(width:height:)`, `videoFilter`) ; `ResizeOperation(preset:)`, `ResizeOperation.group` ; `ImageConverter.downscaledImage(from:maxPixelSize:)`.

- [ ] **Step 1 : tests** — `Tests/OperationTests/ResizeOperationTests.swift` :

```swift
import UniformTypeIdentifiers
import XCTest

final class ResizeOperationTests: XCTestCase {
    private func context(_ dir: URL) throws -> OperationContext {
        OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))), stripsLocation: false,
                         ffmpeg: try Fixtures.ffmpeg())
    }

    private func resize(_ input: URL, _ preset: ResizePreset, in dir: URL) async throws -> URL {
        let outputs = try await ResizeOperation(preset: preset).run(inputs: [input], context: try context(dir)) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    func testPresetArithmetic() {
        XCTAssertEqual(ResizePreset.half.targetLongSide(width: 1600, height: 1200), 800)
        XCTAssertEqual(ResizePreset.long1280.targetLongSide(width: 1600, height: 1200), 1280)
        XCTAssertEqual(ResizePreset.long800.targetLongSide(width: 1200, height: 1600), 800)
        XCTAssertNil(ResizePreset.long1920.targetLongSide(width: 1600, height: 1200), "never enlarge")
        XCTAssertEqual(ResizePreset.allCases.map(\.title), ["50 %", "1920 px", "1280 px", "800 px"])
    }

    func testHalfAnImage() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("shot.png", in: dir, type: .png, width: 400, height: 300)

        let output = try await resize(input, .half, in: dir)

        XCTAssertEqual(output.lastPathComponent, "shot (50 %).png")
        let info = try Fixtures.info(output)
        XCTAssertEqual(info.type, UTType.png.identifier)
        XCTAssertEqual([info.width, info.height], [200, 150])
    }

    func testLongestSidePresetKeepsRatioAndOrientation() async throws {
        let dir = try Fixtures.directory(for: self)
        let landscape = try Fixtures.writeImage("big.jpg", in: dir, type: .jpeg, width: 1600, height: 1200)
        // Stored 1600×1200, shown rotated (portrait 1200×1600).
        let portrait = try Fixtures.writeImage("phone.jpg", in: dir, type: .jpeg, width: 1600, height: 1200, orientation: 6)

        let resizedLandscape = try await resize(landscape, .long800, in: dir)
        let resizedPortrait = try await resize(portrait, .long800, in: dir)

        XCTAssertEqual(resizedLandscape.lastPathComponent, "big (800 px).jpg")
        let landscapeInfo = try Fixtures.info(resizedLandscape)
        let portraitInfo = try Fixtures.info(resizedPortrait)
        XCTAssertEqual([landscapeInfo.width, landscapeInfo.height], [800, 600])
        XCTAssertEqual([portraitInfo.width, portraitInfo.height], [600, 800])
    }

    func testAnImageIsNeverEnlarged() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("small.png", in: dir, type: .png, width: 400, height: 300)

        do {
            _ = try await resize(input, .long1920, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .alreadySmall(than: "1920 px"))
        }
    }

    func testWebPIsResizedAsWebP() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = dir.appending(path: "logo.webp")
        try await WebPEncoder.encode(Fixtures.makeNoiseImage(width: 400, height: 300), quality: 90, to: input,
                                     with: try Fixtures.ffmpeg())

        let info = try Fixtures.info(try await resize(input, .half, in: dir))

        XCTAssertEqual(info.type, UTType.webP.identifier)
        XCTAssertEqual([info.width, info.height], [200, 150])
    }

    func testVideoPresets() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir, size: "1280x720")

        let half = try await resize(input, .half, in: dir)
        let small = try await resize(input, .long800, in: dir)
        let halfProbe = try await Fixtures.ffmpeg().probe(half)
        let smallProbe = try await Fixtures.ffmpeg().probe(small)

        XCTAssertEqual(half.lastPathComponent, "clip (50 %).mp4")
        XCTAssertEqual([halfProbe.width, halfProbe.height], [640, 360])
        XCTAssertEqual([smallProbe.width, smallProbe.height], [800, 450])
        XCTAssertEqual(smallProbe.videoCodec, "h264")
        do {
            _ = try await resize(input, .long1920, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .alreadySmall(than: "1920 px"))
        }
    }
}
```

Ajouter à `OperationRegistryTests` :

```swift
    func testResizeIsOneSegmentWithFourPresets() {
        let segments = registry.segments(for: [URL(fileURLWithPath: "/tmp/a.png")], kind: .tools)
        XCTAssertEqual(segments.map(\.id), ["tool.compress", "tool.resize"])
        XCTAssertEqual(segments[1].title, "Redimensionner")
        XCTAssertEqual(segments[1].children.map(\.id),
                       ["tool.resize.50", "tool.resize.1920", "tool.resize.1280", "tool.resize.800"])
        XCTAssertEqual(ids(["a.bmp"], .tools), ["tool.resize.50", "tool.resize.1920", "tool.resize.1280", "tool.resize.800"])
        XCTAssertTrue(ids(["a.mov"], .tools).contains("tool.resize.800"))
        XCTAssertFalse(ids(["a.pdf"], .tools).contains("tool.resize.800"))
    }
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'ResizePreset' in scope`.

- [ ] **Step 3 : implémenter** — dans `ImageConverter`, après `uprightImage(from:)` :

```swift
    /// First image, upright, downscaled so that its longer side is `maxPixelSize`.
    static func downscaledImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
```

`App/Operations/Tools/ResizeOperation.swift` :

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Presets of "Redimensionner" (§5.4): half size, or a longer side of
/// 1920, 1280 or 800 px. The aspect ratio is kept and nothing is enlarged.
enum ResizePreset: CaseIterable, Sendable {
    case half, long1920, long1280, long800

    var maxLongSide: Int? {
        switch self {
        case .half: nil
        case .long1920: 1920
        case .long1280: 1280
        case .long800: 800
        }
    }

    var id: String { maxLongSide.map { String($0) } ?? "50" }
    var title: String { maxLongSide.map { "\($0) px" } ?? "50 %" }

    /// Longer side of the result, nil when the file is already small enough.
    func targetLongSide(width: Int, height: Int) -> Int? {
        let longSide = max(width, height)
        guard let limit = maxLongSide else { return longSide > 1 ? longSide / 2 : nil }
        return longSide > limit ? limit : nil
    }

    var videoFilter: String {
        maxLongSide.map { VideoScaling.fitting(longSide: $0) } ?? VideoScaling.half
    }
}

/// One preset of "Redimensionner", for images (format kept) and videos
/// (H.264). The four presets share a sub-wheel.
struct ResizeOperation: FileOperation {
    static let group = OperationGroup(id: "tool.resize", title: "Redimensionner", symbol: "aspectratio")

    let preset: ResizePreset

    var id: String { "tool.resize.\(preset.id)" }
    var kind: WheelMode { .tools }
    var title: String { preset.title }
    var symbol: String { "aspectratio" }
    var group: OperationGroup? { Self.group }
    var usesMediaEngine: Bool { true }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy {
            (FileTypes.isImage($0) && ImageRewriter.canRewrite($0)) || FileTypes.isVideo($0)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { progress((Double(index) + $0) / Double(inputs.count)) }
            let type = FileTypes.type(of: input)
            let baseName = "\(input.baseName) (\(preset.title))"
            if FileTypes.isVideo(type) {
                outputs.append(try await resizeVideo(input, baseName: baseName, context: context, progress: share))
            } else {
                outputs.append(try await context.output.commitAsync(baseName: baseName,
                                                                    fileExtension: input.pathExtension.lowercased(),
                                                                    for: input) { temporary in
                    try await resizeImage(input, type: type, to: temporary, context: context)
                })
            }
            share(1)
        }
        return outputs
    }

    private func resizeImage(_ input: URL, type: UTType, to url: URL, context: OperationContext) async throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw OperationError.unreadableImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { throw OperationError.unreadableImage }
        guard let longSide = preset.targetLongSide(width: width, height: height) else {
            throw OperationError.alreadySmall(than: preset.title)
        }
        guard let image = ImageConverter.downscaledImage(from: source, maxPixelSize: longSide) else {
            throw OperationError.unreadableImage
        }
        try await ImageRewriter.write(image, like: type, to: url, quality: nil,
                                      properties: ImageConverter.metadata(of: source, stripsLocation: context.stripsLocation),
                                      ffmpeg: context.ffmpeg)
    }

    private func resizeVideo(_ input: URL, baseName: String, context: OperationContext,
                             progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        let probe: MediaProbe
        do {
            probe = try await ffmpeg.probe(input)
        } catch let error as FFmpegError {
            throw OperationError.unreadableVideo.withDetail(error.description)
        }
        guard probe.videoCodec != nil else { throw OperationError.noVideo }
        if let width = probe.width, let height = probe.height,
           preset.targetLongSide(width: width, height: height) == nil {
            throw OperationError.alreadySmall(than: preset.title)
        }
        let isMOV = FileTypes.type(of: input).conforms(to: .quickTimeMovie)

        return try await context.output.commitAsync(baseName: baseName, fileExtension: isMOV ? "mov" : "mp4",
                                                    for: input) { temporary in
            var arguments = ["-i", input.path, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn",
                             "-vf", preset.videoFilter,
                             "-c:v", "h264_videotoolbox", "-q:v", MediaOutput.videoQuality, "-pix_fmt", "yuv420p",
                             "-tag:v", "avc1"]
            arguments += probe.audioCodec == "aac" ? ["-c:a", "copy"] : ["-c:a", "aac_at", "-b:a", "192k"]
            if !isMOV { arguments += ["-movflags", "+faststart"] }
            do {
                try await ffmpeg.convert(arguments + [temporary.path], duration: probe.duration, progress: progress)
            } catch let error as FFmpegError {
                throw OperationError.unreadableVideo.withDetail(error.description)
            }
        }
    }
}
```

Dans `OperationRegistry.standard`, après `operations.append(CompressOperation())` :

```swift
        operations += ResizePreset.allCases.map { ResizeOperation(preset: $0) as any FileOperation }
```

- [ ] **Step 4 : lancer les tests** — `scripts/test.sh` → `TESTS OK`.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 5: Redimensionner with four presets"`.

---

### Task 4 : la sous-roue à l'écran

**Files :**
- Modify : `App/Wheel/WheelView.swift` (titre), `App/Wheel/WheelController.swift`, `App/GestureCoordinator.swift`

**Interfaces :**
- Consumes : `WheelModel.open/goBack/title`, `WheelItem.back`, `OperationRegistry.segments(for:kind:)`.
- Produces : `WheelTitleView.setMode(_:title:)` ; survol prolongé de « Plus… », « Retour » ou d'un segment parent → navigation ; drop accepté uniquement sur un segment feuille.

- [ ] **Step 1 : titre** — dans `WheelTitleView`, `func setMode(_ mode: WheelMode) {` devient `func setMode(_ mode: WheelMode, title: String? = nil) {` et `string: mode.title,` devient `string: title ?? mode.title,`. Mettre à jour le commentaire de la classe : `/// "Convertir  ⇧ ⌘ ⌃" (or the open sub-wheel's title) in a small capsule…`.

- [ ] **Step 2 : contrôleur** — dans `WheelController` :
  - commentaire de `pagingDelay` : `/// Lingering this long on "Plus…", "Retour" or a sub-wheel segment navigates (§5.2).` ; renommer `pagingTimer` en `navigationTimer` partout ;
  - dans `load(_:)`, supprimer la ligne `titleView.setMode(mode)` ; dans `reloadItems()`, après `guard let model else { return }`, ajouter `titleView.setMode(model.mode, title: model.title)` ;
  - remplacer `setHoveredSlot(_:)` et `turnPage()` par :

```swift
    /// What lingering on a slot does.
    private enum Navigation {
        case nextPage, open(WheelSegment), back
    }

    private func navigation(for item: WheelItem) -> Navigation? {
        switch item {
        case .more: .nextPage
        case .back: .back
        case .segment(let segment): segment.children.isEmpty ? nil : .open(segment)
        }
    }

    fileprivate func setHoveredSlot(_ slot: Int?) {
        guard slot != hoveredSlot else { return }
        hoveredSlot = slot
        wheelView.highlightedSlot = slot
        navigationTimer?.invalidate()
        navigationTimer = nil
        guard let slot, let model else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        if let navigation = navigation(for: model.items[slot]) {
            navigationTimer = Timer.scheduledTimer(withTimeInterval: Self.pagingDelay, repeats: false) { _ in
                MainActor.assumeIsolated { self.navigate(navigation) }
            }
        }
    }

    private func navigate(_ navigation: Navigation) {
        guard isVisible else { return }
        switch navigation {
        case .nextPage: model?.nextPage()
        case .open(let segment): model?.open(segment)
        case .back: model?.goBack()
        }
        reloadItems()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
```

  - dans `segment(at:)`, la ligne `if case .segment(let segment) = model.items[slot] { return (slot, segment) }` devient :

```swift
        // Only leaf segments take the drop; a parent opens its sub-wheel instead.
        if case .segment(let segment) = model.items[slot], segment.children.isEmpty { return (slot, segment) }
```

  - le commentaire `// Only a real segment accepts the drop; the centre and "Plus…" refuse it.` devient `// Only a leaf segment accepts the drop; the centre, "Plus…", "Retour" and parents refuse it.`

- [ ] **Step 3 : coordinateur** — dans `GestureCoordinator.start()`, `registry.operations(for: files, kind: mode).map(\.segment)` devient `registry.segments(for: files, kind: mode)`. Dans `performDebugLaunchArguments()`, la capture différée laisse le temps à une sous-roue de s'ouvrir :

```swift
        if let path = defaults.string(forKey: "debugSnapshot") {
            // Leaves time for a hovered parent to open its sub-wheel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [wheel] in
                wheel.debugSnapshot(to: URL(fileURLWithPath: path))
            }
        }
```

- [ ] **Step 4 : build + rendu** — `scripts/build.sh Debug` → `BUILD OK` ; `scripts/test.sh` → `TESTS OK` ; puis rendus :

```bash
APP=build/Build/Products/Debug/Pivot.app; S=<scratchpad>
open -n -g $APP --args -debugWheel tools -debugFiles '("/tmp/a.png")' -debugSnapshot $S/tools.png; sleep 2; pkill -x Pivot
open -n -g $APP --args -debugWheel tools -debugFiles '("/tmp/a.png")' -debugSlot 1 -debugSnapshot $S/resize.png; sleep 2; pkill -x Pivot
open -n -g $APP --args -debugWheel actions -debugFiles '("/tmp/Vacances/")' -debugSnapshot $S/actions.png; sleep 2; pkill -x Pivot
```

Attendu : `tools.png` montre « Compresser » et « Redimensionner » ; `resize.png` montre le titre « Redimensionner » et 50 % / 1920 px / 1280 px / 800 px / Retour ; `actions.png` (après la tâche 5) les trois actions pour un dossier.

- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 5: sub-wheel navigation on screen"`.

---

### Task 5 : Actions et message de pastille par opération

**Files :**
- Create : `App/Operations/Actions/CopyPathAction.swift`, `App/Operations/Actions/RevealAction.swift`, `App/Operations/Actions/AirDropAction.swift`, `Tests/OperationTests/ActionTests.swift`
- Modify : `App/Operations/FileOperation.swift`, `App/Operations/OperationRegistry.swift`, `App/Feedback/HUDToast.swift`, `App/Output/JobQueue.swift`, `Tests/OperationTests/OperationRegistryTests.swift`

**Interfaces :**
- Produces : `FileOperation.completionMessage(inputs:outputs:) -> String?` (défaut : « x créé » / « n fichiers créés ») ; `CopyPathAction(pasteboardName:)`, `RevealAction()`, `AirDropAction()` ; `HUDController.succeed(_:message:outputs:symbol:)` ; `HUDToast.showSuccess(message:outputs:symbol:)`.

- [ ] **Step 1 : tests** — `Tests/OperationTests/ActionTests.swift` :

```swift
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
}
```

Ajouter à `OperationRegistryTests` :

```swift
    func testActionsAreOfferedForEverythingAndFoldersGetOnlyActions() {
        let actions = ["action.copyPath", "action.reveal", "action.airdrop"]
        XCTAssertEqual(ids(["Vacances/"], .actions), actions)
        XCTAssertEqual(ids(["a.png", "Vacances/", "notes.txt"], .actions), actions)
        XCTAssertEqual(ids(["Vacances/"], .convert) + ids(["Vacances/"], .tools), [])
    }
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'CopyPathAction' in scope`.

- [ ] **Step 3 : implémenter** — dans le protocole `FileOperation`, après `var group: OperationGroup? { get }` :

```swift
    /// Text of the confirmation pill, nil for none (the action shows its own result).
    func completionMessage(inputs: [URL], outputs: [URL]) -> String?
```

et dans l'extension :

```swift
    func completionMessage(inputs: [URL], outputs: [URL]) -> String? {
        outputs.count == 1 ? "\(outputs[0].lastPathComponent) créé" : "\(outputs.count) fichiers créés"
    }
```

`App/Operations/Actions/CopyPathAction.swift` :

```swift
import AppKit
import UniformTypeIdentifiers

/// "Copier le chemin" (§5.4): POSIX paths, one per line.
struct CopyPathAction: FileOperation {
    let id = "action.copyPath"
    let kind = WheelMode.actions
    let title = "Copier le chemin"
    let symbol = "doc.on.clipboard"
    /// The general pasteboard; a private one in tests.
    var pasteboardName = NSPasteboard.Name.general.rawValue

    func accepts(_ types: [UTType]) -> Bool { !types.isEmpty }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let text = inputs.map(\.path).joined(separator: "\n")
        await MainActor.run {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        return []
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? {
        inputs.count == 1 ? "Chemin copié" : "\(inputs.count) chemins copiés"
    }
}
```

`App/Operations/Actions/RevealAction.swift` :

```swift
import AppKit
import UniformTypeIdentifiers

/// "Afficher dans le Finder" (§5.4). The Finder window is the confirmation.
struct RevealAction: FileOperation {
    let id = "action.reveal"
    let kind = WheelMode.actions
    let title = "Afficher dans le Finder"
    let symbol = "folder"

    func accepts(_ types: [UTType]) -> Bool { !types.isEmpty }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(inputs) }
        return []
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? { nil }
}
```

`App/Operations/Actions/AirDropAction.swift` :

```swift
import AppKit
import UniformTypeIdentifiers

/// "AirDrop" (§5.4) through the system sharing service, whose own window
/// is the confirmation. Pivot comes to the front so that window shows.
struct AirDropAction: FileOperation {
    let id = "action.airdrop"
    let kind = WheelMode.actions
    let title = "AirDrop"
    let symbol = "airplayaudio"

    func accepts(_ types: [UTType]) -> Bool { !types.isEmpty }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try await MainActor.run {
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: inputs) else {
                throw OperationError.airDropUnavailable
            }
            NSApp.activate()
            service.perform(withItems: inputs)
        }
        return []
    }

    func completionMessage(inputs: [URL], outputs: [URL]) -> String? { nil }
}
```

`OperationRegistry.standard`, après la ligne des `ResizeOperation` :

```swift
        operations += [CopyPathAction(), RevealAction(), AirDropAction()] as [any FileOperation]
```

`App/Feedback/HUDToast.swift` :
  - `HUDController.succeed` devient :

```swift
    func succeed(_ toast: HUDToast, message: String, outputs: [URL], symbol: String) {
        toast.showSuccess(message: message, outputs: outputs, symbol: symbol)
        present(toast)
        remove(toast, after: Self.successDuration)
    }
```

  - `HUDToast.showSuccess(outputs:)` devient :

```swift
    func showSuccess(message: String, outputs: [URL], symbol: String) {
        isRunning = false
        self.outputs = outputs
        let icon = outputs.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: message)
        content.configure(icon: icon, tint: outputs.isEmpty ? .labelColor : nil, text: message, progress: nil)
    }
```

`App/Output/JobQueue.swift`, dans `finish`, le cas `.success` devient :

```swift
        case .success(let outputs):
            let paths = outputs.map(\.path).joined(separator: ", ")
            AppInfo.jobLog.info("Job \(operation.id, privacy: .public) done: \(paths, privacy: .public)")
            if let message = operation.completionMessage(inputs: inputs, outputs: outputs) {
                hud.succeed(toast, message: message, outputs: outputs, symbol: operation.symbol)
            } else {
                hud.cancel(toast)
            }
            if !outputs.isEmpty, SettingsStore.playsCompletionSound {
                AudioServicesPlaySystemSound(Self.completionSound)
            }
```

- [ ] **Step 4 : tests + build** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK` ; rendu `actions.png` de la tâche 4 (dossier → trois actions).
- [ ] **Step 5 : essai réel** — `-debugRun action.copyPath -debugFiles '("/tmp/a.png","/tmp/b.png")'` puis `pbpaste` → deux lignes ; `-debugRun tool.compress` sur un JPEG de test et `-debugRun tool.resize.800` sur une vidéo de test → fichiers suffixés dans `Convertis`, puis les supprimer. (`pbpaste` remplace le presse-papiers de Raphaël : le sauvegarder avant avec `pbpaste > <scratchpad>/pb.txt` et le restaurer après avec `pbcopy < <scratchpad>/pb.txt`.)
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 5: copy path, reveal and AirDrop actions"`.

---

### Task 6 : vérification finale et documentation

- [ ] **Step 1 : vérification** (superpowers:verification-before-completion) — tests complets, build, `codesign --verify --deep --strict`, contraintes globales relues ligne par ligne ; requêtes `tccd` lors d'un `-debugRun tool.compress` sur une vidéo.
- [ ] **Step 2 : CLAUDE.md** — ligne de phase 5 → 🟡 avec l'état réel, décisions prises (format conservé, pas d'agrandissement, refus si pas plus petit, BMP).
- [ ] **Step 3 : commit + push**.
- [ ] **Step 4 : résumé à Raphaël** avec la checklist manuelle : ⌘ sur une photo → Compresser (fichier « (compressé) » plus petit) ; ⌘ → survol de « Redimensionner » → sous-roue → 1280 px ; « Retour » ; vidéo 4K → Compresser (HEVC 1080p) ; PDF scanné → Compresser ; PNG déjà optimisé → message ; ⌃ sur plusieurs fichiers → Copier le chemin (coller dans TextEdit) ; ⌃ → Afficher dans le Finder ; ⌃ → AirDrop (fenêtre AirDrop) ; dossier glissé → seulement les actions ; drop sur « Redimensionner » lui-même refusé.
