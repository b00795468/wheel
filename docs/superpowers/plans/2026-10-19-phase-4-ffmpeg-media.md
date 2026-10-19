# Phase 4 — ffmpeg embarqué + conversions audio / vidéo / GIF / WebP — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Ce projet impose `superpowers:executing-plans` (voir CLAUDE.md, section Skills).

**Goal :** déposer une vidéo ou un fichier audio sur la roue « Convertir » produit le fichier converti par un ffmpeg embarqué dans l'app, avec progression, annulation et au plus deux tâches médias simultanées ; les images gagnent la sortie WebP.

**Architecture :** `scripts/fetch-ffmpeg.sh` télécharge un build figé (martin-riedl.de 9.0.2, SHA-256 épinglés) dans `Vendor/ffmpeg/` (non versionné) ; une phase de build « Embed ffmpeg » le copie dans `Contents/Resources/bin/`, retire la quarantaine et le re-signe avec l'identité de l'app. `FFmpegRunner` lance ffmpeg / ffprobe (`Process`), lit la progression sur `-progress pipe:1` et termine le processus à l'annulation. `MediaOutput` choisit les arguments selon ce que ffprobe a trouvé (remux sans ré-encodage quand c'est possible) ; `MediaConvertOperation` et `ImageToWebPOperation` s'ajoutent au registre. `JobQueue` limite les tâches médias avec un `AsyncSemaphore`.

**Tech stack :** Swift 5, Foundation `Process`, ImageIO, XCTest ; ffmpeg 9.0.2 statique arm64 (VideoToolbox, AudioToolbox, libmp3lame, libwebp). Aucun package Swift.

**Spec :** `SPEC.md` (§3 moteurs, §5.4 périmètre, §5.6 exécution, §7 tests, §9 phase 4).

## Contraintes globales

- ffmpeg statique arm64 dans `Contents/Resources/bin/ffmpeg` (+ `ffprobe`), dépendant **uniquement** de bibliothèques système (`otool -L`, aucun `/opt/homebrew`) (§3).
- Binaire signé lors du build (phase « Run Script »), attribut quarantaine retiré (§3).
- Source validée par Raphaël : `https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/` ; SHA-256 des zips : ffmpeg `c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924`, ffprobe `fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6`.
- Encodage vidéo matériel `h264_videotoolbox` ; progression via `-progress pipe:1` + durée via `ffprobe` (§3).
- Vidéo (MP4, MOV, MKV, WebM, AVI) → MP4 (H.264), MOV, GIF (palette optimisée, 15 fps, largeur max 720), MP3, M4A (§5.4).
- Audio (MP3, M4A, WAV, FLAC, AIFF, OGG) → MP3 (192k), M4A (AAC 256k), WAV, FLAC (§5.4).
- Images → WebP (reporté de la phase 3 : ImageIO ne l'encode pas).
- Ne jamais proposer le format d'origine ; intersection multi-fichiers (§5.2, §5.4).
- Max 2 tâches médias en parallèle ; images en parallèle ; une nouvelle opération se met en file, sans bloquer (§5.6).
- Progression + annulation pour les tâches > 1 s (pastille existante) ; erreurs en français humain, détail technique dans le log (§5.6).
- Jamais d'écrasement ; écriture temporaire puis déplacement atomique (§5.5, `OutputLocator`).
- Aucun impact CPU au repos ; à la fermeture de l'app, aucun ffmpeg orphelin.
- Interface en français ; code et commentaires en anglais ; zéro package externe.

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `scripts/fetch-ffmpeg.sh` (nouveau) | Téléchargement figé + vérification SHA-256 + contrôle `otool -L` |
| `.gitignore` | `Vendor/` |
| `project.yml` | Phase de build « Embed ffmpeg » ; sources de test |
| `scripts/build.sh`, `scripts/test.sh` | Récupèrent ffmpeg s'il manque |
| `App/Operations/FileTypes.swift` | Familles vidéo et audio |
| `App/Operations/FileOperation.swift` | `OperationContext.ffmpeg`, `usesMediaEngine`, erreurs médias, `OperationError.detail` |
| `App/Output/OutputLocator.swift` | `commitAsync` (écrivain async) via un `Staging` partagé |
| `App/Operations/Engines/FFmpegRunner.swift` (nouveau) | `FFmpegRunner`, `MediaProbe`, `FFmpegError` |
| `App/Operations/Converters/MediaOutput.swift` (nouveau) | Formats audio/vidéo et arguments ffmpeg |
| `App/Operations/Converters/MediaConvertOperation.swift` (nouveau) | Opération audio/vidéo |
| `App/Operations/Converters/ImageToWebPOperation.swift` (nouveau) | Opération WebP |
| `App/Operations/OperationRegistry.swift` | Nouvelles opérations |
| `App/Output/AsyncSemaphore.swift` (nouveau) | Sémaphore async annulable |
| `App/Output/JobQueue.swift` | Créneaux médias, ffmpeg dans le contexte, `cancelAll()` |
| `App/GestureCoordinator.swift`, `App/AppDelegate.swift` | Annulation de tout à la fermeture |
| `Tests/Support/Fixtures.swift` | ffmpeg de test, vidéos/audios générés, `ProgressRecorder` partagé |
| `Tests/OperationTests/*` | Types, runner, arguments, opérations, registre |
| `Tests/OutputLocatorTests/OutputLocatorTests.swift` | `commitAsync` |
| `Tests/OutputLocatorTests/AsyncSemaphoreTests.swift` (nouveau) | Limite et annulation |

---

### Task 1 : ffmpeg récupéré, embarqué et signé

**Files :**
- Create : `scripts/fetch-ffmpeg.sh`
- Modify : `.gitignore`, `project.yml`, `scripts/build.sh`, `scripts/test.sh`

**Interfaces :**
- Produces : `Vendor/ffmpeg/ffmpeg`, `Vendor/ffmpeg/ffprobe` (exécutables) ; dans l'app : `Pivot.app/Contents/Resources/bin/ffmpeg` et `ffprobe`, signés avec l'identité de l'app.

- [ ] **Step 1 : script de récupération** — `scripts/fetch-ffmpeg.sh` (puis `chmod +x`) :

```bash
#!/bin/bash
# Downloads the static arm64 ffmpeg/ffprobe build validated for Pivot (§3)
# into Vendor/ffmpeg/, checking pinned SHA-256 sums. Not versioned (size).
# Usage: scripts/fetch-ffmpeg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="9.0.2"
BASE_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_${VERSION}"
DEST="Vendor/ffmpeg"
# SHA-256 of the zips, as published next to them (checked on 2026-10-19).
SHA_ffmpeg="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
SHA_ffprobe="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"

mkdir -p "$DEST"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for tool in ffmpeg ffprobe; do
  if [ -x "$DEST/$tool" ] && [ "$(cat "$DEST/$tool.version" 2>/dev/null)" = "$VERSION" ]; then
    echo "${tool} ${VERSION} déjà présent"
    continue
  fi
  echo "Téléchargement de ${tool} ${VERSION}…"
  curl -fsSL -o "$TMP/$tool.zip" "$BASE_URL/$tool.zip"
  expected_var="SHA_$tool"
  actual=$(shasum -a 256 "$TMP/$tool.zip" | cut -d' ' -f1)
  if [ "$actual" != "${!expected_var}" ]; then
    echo "SHA-256 inattendu pour ${tool}.zip : ${actual}" >&2
    exit 1
  fi
  ditto -x -k "$TMP/$tool.zip" "$TMP/$tool"
  ditto "$TMP/$tool/$tool" "$DEST/$tool"
  echo "$VERSION" > "$DEST/$tool.version"
done

# Only system libraries are allowed (§3): no Homebrew or /usr/local paths.
if otool -L "$DEST/ffmpeg" "$DEST/ffprobe" | grep -E '/opt/|/usr/local/'; then
  echo "Dépendance non système détectée" >&2
  exit 1
fi
echo "ffmpeg ${VERSION} prêt dans ${DEST}"
```

- [ ] **Step 2 : ignorer `Vendor/`** — ajouter la ligne `Vendor/` à `.gitignore`.

- [ ] **Step 3 : récupérer automatiquement** — dans `scripts/build.sh` **et** `scripts/test.sh`, juste avant `xcodegen generate --quiet` :

```bash
# ffmpeg is embedded in the app and used by the tests (§3).
if [ ! -x Vendor/ffmpeg/ffmpeg ] || [ ! -x Vendor/ffmpeg/ffprobe ]; then
  scripts/fetch-ffmpeg.sh
fi
```

- [ ] **Step 4 : phase de build** — dans `project.yml`, target `Pivot`, entre le bloc `settings` et `scheme` :

```yaml
    postBuildScripts:
      # Copies the vendored ffmpeg into Contents/Resources/bin, drops the
      # quarantine flag and re-signs it with the app's identity (§3). Xcode
      # signs the app itself after every build phase.
      - name: Embed ffmpeg
        shell: /bin/bash
        basedOnDependencyAnalysis: true
        inputFiles:
          - $(SRCROOT)/Vendor/ffmpeg/ffmpeg
          - $(SRCROOT)/Vendor/ffmpeg/ffprobe
        outputFiles:
          - $(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/bin/ffmpeg
          - $(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/bin/ffprobe
        script: |
          set -euo pipefail
          BIN="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin"
          mkdir -p "$BIN"
          for tool in ffmpeg ffprobe; do
            SRC="$SRCROOT/Vendor/ffmpeg/$tool"
            if [ ! -x "$SRC" ]; then
              echo "error: $SRC manquant, lancer scripts/fetch-ffmpeg.sh"
              exit 1
            fi
            ditto "$SRC" "$BIN/$tool"
            xattr -d com.apple.quarantine "$BIN/$tool" 2>/dev/null || true
            codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$BIN/$tool"
          done
```

- [ ] **Step 5 : vérifier** —

```bash
scripts/fetch-ffmpeg.sh && scripts/build.sh Debug
APP=build/Build/Products/Debug/Pivot.app
ls -la $APP/Contents/Resources/bin/
codesign -dv --verbose=2 $APP/Contents/Resources/bin/ffmpeg 2>&1 | grep -E 'Authority|Signature='
codesign --verify --deep --strict $APP && echo "app verify OK"
$APP/Contents/Resources/bin/ffmpeg -hide_banner -version | head -1
otool -L $APP/Contents/Resources/bin/ffmpeg | grep -cE '/opt/|/usr/local/'   # attendu : 0
git status --short   # Vendor/ absent
```

Attendu : deux binaires ~66 Mo, `Authority=Pivot Dev` (ou `Signature=adhoc` sans certificat), `app verify OK`, `ffmpeg version 9.0.2-…`, `0`.

- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 4: fetch, embed and sign ffmpeg/ffprobe"`.

---

### Task 2 : socle — types médias, contexte, erreurs, écriture async

**Files :**
- Modify : `App/Operations/FileTypes.swift`, `App/Operations/FileOperation.swift`, `App/Output/OutputLocator.swift`
- Modify : `Tests/OperationTests/FileTypesTests.swift`, `Tests/OutputLocatorTests/OutputLocatorTests.swift`

**Interfaces :**
- Produces : `FileTypes.isVideo(_:)`, `FileTypes.isAudio(_:)`, `FileTypes.m4a`, `FileTypes.flac`, `FileTypes.videoInputs`, `FileTypes.audioInputs` ; `OperationContext(output:stripsLocation:ffmpeg:)` (`ffmpeg` défaut `nil`) ; `FileOperation.usesMediaEngine` (défaut `false`) ; `OperationError.detail`, `withDetail(_:)`, `.unreadableVideo`, `.unreadableAudio`, `.noAudio`, `.noVideo`, `.engineMissing` ; `OutputLocator.commitAsync(baseName:fileExtension:for:write:) async throws -> URL`.
- Consumes : `FFmpegRunner` (type déclaré en tâche 3 — pour que la tâche 2 compile seule, cette tâche crée `App/Operations/Engines/FFmpegRunner.swift` avec uniquement le squelette ci-dessous ; la tâche 3 le remplace).

- [ ] **Step 1 : tests** — ajouter à `FileTypesTests` :

```swift
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
```

ajouter à `OutputLocatorTests` :

```swift
    func testCommitAsyncWritesThroughAnAsyncWriter() async throws {
        let dir = try Fixtures.directory(for: self)
        let locator = OutputLocator(destination: .custom(dir))
        let input = dir.appending(path: "clip.mov")

        let output = try await locator.commitAsync(baseName: "clip", fileExtension: "mp4", for: input) { url in
            try await Task.sleep(for: .milliseconds(10))
            try Data("video".utf8).write(to: url)
        }

        XCTAssertEqual(output.lastPathComponent, "clip.mp4")
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "video")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["clip.mp4"])
    }

    func testOperationErrorsCompareByMessageAndKeepTheirDetail() {
        let detailed = OperationError.unreadableVideo.withDetail("moov atom not found")
        XCTAssertEqual(detailed, .unreadableVideo)
        XCTAssertEqual(detailed.detail, "moov atom not found")
        XCTAssertEqual(detailed.errorDescription, "Ce fichier vidéo semble corrompu ou illisible.")
    }
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `type 'FileTypes' has no member 'isVideo'`, `commitAsync`…

- [ ] **Step 3 : implémenter** — dans `FileTypes`, après `imageInputs` :

```swift
    // Created from extensions, which always yields a type (declared or dynamic).
    static let m4a = UTType(filenameExtension: "m4a")!
    static let flac = UTType(filenameExtension: "flac")!
    private static let mkv = UTType(filenameExtension: "mkv")!
    private static let webm = UTType(filenameExtension: "webm")!
    private static let ogg = UTType(filenameExtension: "ogg")!

    /// Video and audio formats accepted as input (§5.4).
    static let videoInputs: [UTType] = [.mpeg4Movie, .quickTimeMovie, mkv, webm, .avi]
    static let audioInputs: [UTType] = [.mp3, .mpeg4Audio, m4a, .wav, flac, .aiff, ogg]
```

et après `isPDF` :

```swift
    static func isVideo(_ type: UTType) -> Bool {
        videoInputs.contains { type.conforms(to: $0) }
    }

    static func isAudio(_ type: UTType) -> Bool {
        audioInputs.contains { type.conforms(to: $0) }
    }
```

`App/Operations/FileOperation.swift` devient :

```swift
import Foundation
import UniformTypeIdentifiers

/// What an operation needs besides its inputs.
struct OperationContext: Sendable {
    let output: OutputLocator
    /// Drop GPS metadata from images (§5.5, off by default).
    let stripsLocation: Bool
    /// The embedded ffmpeg, nil when the app bundle lacks it.
    var ffmpeg: FFmpegRunner? = nil
}

/// One segment of a wheel. Adding a format means adding an operation to
/// `OperationRegistry.standard`, without touching the wheel (§4).
protocol FileOperation: Sendable {
    /// Stable identifier, e.g. "convert.png".
    var id: String { get }
    var kind: WheelMode { get }
    var title: String { get }
    var symbol: String { get }
    /// Long-running ffmpeg work, limited to a few concurrent jobs (§5.6).
    var usesMediaEngine: Bool { get }
    /// Whether the operation applies to files of all these types at once.
    func accepts(_ types: [UTType]) -> Bool
    /// Runs off the main thread. Returns the created files or folders.
    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL]
}

extension FileOperation {
    var segment: WheelSegment { WheelSegment(id: id, title: title, symbol: symbol) }
    var usesMediaEngine: Bool { false }
}

/// A failure the HUD can show as is: French, human, no jargon (§5.6).
/// `detail` carries the technical cause, for the log file only.
struct OperationError: LocalizedError, Equatable {
    let message: String
    var detail: String? = nil
    var errorDescription: String? { message }

    func withDetail(_ detail: String) -> OperationError {
        OperationError(message: message, detail: detail)
    }

    /// Two errors are the same when the user reads the same message.
    static func == (lhs: OperationError, rhs: OperationError) -> Bool {
        lhs.message == rhs.message
    }

    static let unreadableImage = OperationError(message: "Cette image semble corrompue ou illisible.")
    static let unreadablePDF = OperationError(message: "Ce PDF semble corrompu ou illisible.")
    static let lockedPDF = OperationError(message: "Ce PDF est protégé par un mot de passe.")
    static let writeFailed = OperationError(message: "Impossible d'enregistrer le fichier converti.")
    static let unreadableVideo = OperationError(message: "Ce fichier vidéo semble corrompu ou illisible.")
    static let unreadableAudio = OperationError(message: "Ce fichier audio semble corrompu ou illisible.")
    static let noAudio = OperationError(message: "Cette vidéo ne contient pas de son.")
    static let noVideo = OperationError(message: "Ce fichier ne contient pas d'image vidéo.")
    static let engineMissing = OperationError(message: "Le moteur audio et vidéo est introuvable. Réinstallez l'application.")
}
```

Squelette temporaire `App/Operations/Engines/FFmpegRunner.swift` (remplacé en tâche 3) :

```swift
import Foundation

/// Runs the embedded ffmpeg / ffprobe. Completed in the next task.
struct FFmpegRunner: Sendable {
    let ffmpeg: URL
    let ffprobe: URL
}
```

Dans `App/Output/OutputLocator.swift`, remplacer `commit(baseName:fileExtension:for:write:)` par :

```swift
    /// Lets `write` produce the file at a temporary URL on the same volume,
    /// then moves it to a free name and gives it the input's creation date.
    func commit(baseName: String, fileExtension: String, for input: URL,
                write: (URL) throws -> Void) throws -> URL {
        let staging = try Staging(locator: self, baseName: baseName, fileExtension: fileExtension, input: input)
        defer { staging.cleanUp() }
        try write(staging.temporary)
        return try staging.place()
    }

    /// `commit` for writers that are async, such as ffmpeg.
    func commitAsync(baseName: String, fileExtension: String, for input: URL,
                     write: (URL) async throws -> Void) async throws -> URL {
        let staging = try Staging(locator: self, baseName: baseName, fileExtension: fileExtension, input: input)
        defer { staging.cleanUp() }
        try await write(staging.temporary)
        return try staging.place()
    }

    /// A temporary file on the output volume, moved to a free name once written.
    private struct Staging {
        let directory: URL
        let folder: URL
        let temporary: URL
        let baseName: String
        let fileExtension: String
        let input: URL

        init(locator: OutputLocator, baseName: String, fileExtension: String, input: URL) throws {
            directory = try locator.directory(for: input)
            folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: directory, create: true)
            temporary = folder.appending(path: "\(baseName).\(fileExtension)")
            self.baseName = baseName
            self.fileExtension = fileExtension
            self.input = input
        }

        func place() throws -> URL {
            // Another job may take the same name between the check and the move.
            while true {
                let target = OutputLocator.availableURL(in: directory, baseName: baseName, fileExtension: fileExtension)
                do {
                    try FileManager.default.moveItem(at: temporary, to: target)
                    OutputLocator.copyCreationDate(from: input, to: target)
                    return target
                } catch CocoaError.fileWriteFileExists {
                    continue
                }
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
        }
    }
```

- [ ] **Step 4 : lancer les tests** — `scripts/test.sh` → `TESTS OK` (tous les anciens tests compris).
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 4: media file types, async commit, media errors"`.

---

### Task 3 : FFmpegRunner (ffprobe, progression, annulation)

**Files :**
- Modify : `App/Operations/Engines/FFmpegRunner.swift` (version complète), `Tests/Support/Fixtures.swift`, `Tests/OperationTests/ConvertOperationTests.swift`
- Create : `Tests/OperationTests/FFmpegRunnerTests.swift`

**Interfaces :**
- Produces : `FFmpegRunner(ffmpeg:ffprobe:)`, `FFmpegRunner.bundled`, `isAvailable`, `probe(_:) async throws -> MediaProbe`, `convert(_ arguments: [String], duration: Double?, progress:) async throws` ; `MediaProbe(duration:videoCodec:audioCodec:)`, `MediaProbe.parse(_: Data) throws` ; `FFmpegError(status:log:)` ; tests : `Fixtures.ffmpeg()`, `Fixtures.writeVideo`, `Fixtures.writeAudio`, `Fixtures.codecs(of:)`, `Fixtures.runTool`, `ProgressRecorder`.

- [ ] **Step 1 : fixtures** — dans `Tests/OperationTests/ConvertOperationTests.swift`, supprimer la classe privée `ProgressRecorder` (elle passe dans les fixtures). Ajouter à la fin de `Tests/Support/Fixtures.swift` :

```swift
/// Thread-safe progress sink for @Sendable callbacks.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []
    func record(_ value: Double) { lock.withLock { recorded.append(value) } }
    var values: [Double] { lock.withLock { recorded } }
    var last: Double? { values.last }
}

extension Fixtures {
    /// ffmpeg / ffprobe fetched by scripts/fetch-ffmpeg.sh; tests needing them are skipped otherwise.
    static func ffmpeg() throws -> FFmpegRunner {
        let vendor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Vendor/ffmpeg")
        let runner = FFmpegRunner(ffmpeg: vendor.appending(path: "ffmpeg"), ffprobe: vendor.appending(path: "ffprobe"))
        guard runner.isAvailable else { throw XCTSkip("Vendor/ffmpeg missing: run scripts/fetch-ffmpeg.sh") }
        return runner
    }

    /// Test video from ffmpeg's lavfi sources: colour bars, plus a 440 Hz tone when `audio`.
    @discardableResult
    static func writeVideo(_ name: String, in directory: URL, seconds: Int = 2, codec: String = "h264_videotoolbox",
                           audio: Bool = true, size: String = "1280x720") throws -> URL {
        let url = directory.appending(path: name)
        var arguments = ["-hide_banner", "-loglevel", "error",
                         "-f", "lavfi", "-i", "testsrc2=duration=\(seconds):size=\(size):rate=30"]
        if audio {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=440:duration=\(seconds)", "-c:a", "aac"]
        }
        arguments += ["-c:v", codec, "-pix_fmt", "yuv420p", "-shortest", url.path]
        try runTool(try ffmpeg().ffmpeg, arguments)
        return url
    }

    @discardableResult
    static func writeAudio(_ name: String, in directory: URL, seconds: Int = 2) throws -> URL {
        let url = directory.appending(path: name)
        try runTool(try ffmpeg().ffmpeg, ["-hide_banner", "-loglevel", "error",
                                          "-f", "lavfi", "-i", "sine=frequency=440:duration=\(seconds)", url.path])
        return url
    }

    /// Codec name of every stream, via ffprobe.
    static func codecs(of url: URL) throws -> [String] {
        let output = try runTool(try ffmpeg().ffprobe, ["-v", "error", "-show_entries", "stream=codec_name",
                                                         "-of", "csv=p=0", url.path])
        return output.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ", ")) }
    }

    @discardableResult
    static func runTool(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 2 : tests** — `Tests/OperationTests/FFmpegRunnerTests.swift` :

```swift
import XCTest

final class FFmpegRunnerTests: XCTestCase {
    func testProbeJSONIsParsed() throws {
        let json = #"{"streams":[{"codec_name":"h264","codec_type":"video","disposition":{"attached_pic":0}},{"codec_name":"aac","codec_type":"audio","disposition":{"attached_pic":0}}],"format":{"duration":"3.000000"}}"#
        XCTAssertEqual(try MediaProbe.parse(Data(json.utf8)),
                       MediaProbe(duration: 3, videoCodec: "h264", audioCodec: "aac"))
    }

    func testCoverArtIsNotAVideoStream() throws {
        let json = #"{"streams":[{"codec_name":"mp3","codec_type":"audio","disposition":{"attached_pic":0}},{"codec_name":"mjpeg","codec_type":"video","disposition":{"attached_pic":1}}],"format":{"duration":"N/A"}}"#
        XCTAssertEqual(try MediaProbe.parse(Data(json.utf8)),
                       MediaProbe(duration: nil, videoCodec: nil, audioCodec: "mp3"))
        XCTAssertThrowsError(try MediaProbe.parse(Data("not json".utf8)))
    }

    func testProbeReadsDurationAndCodecs() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)
        let video = try Fixtures.writeVideo("clip.mp4", in: dir, seconds: 2)

        let probe = try await ffmpeg.probe(video)

        XCTAssertEqual(probe.duration ?? 0, 2, accuracy: 0.2)
        XCTAssertEqual(probe.videoCodec, "h264")
        XCTAssertEqual(probe.audioCodec, "aac")
    }

    func testConvertReportsProgressUpToTheEnd() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)
        let video = try Fixtures.writeVideo("clip.mp4", in: dir, seconds: 4)
        let output = dir.appending(path: "out.mov")
        let recorder = ProgressRecorder()

        try await ffmpeg.convert(["-i", video.path, "-c:v", "h264_videotoolbox", "-an", output.path], duration: 4) {
            recorder.record($0)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(recorder.values.isEmpty)
        XCTAssertEqual(recorder.values, recorder.values.sorted())
        XCTAssertGreaterThan(recorder.last ?? 0, 0.9)
    }

    func testFailureCarriesTheFFmpegLog() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)

        do {
            try await ffmpeg.convert(["-i", dir.appending(path: "missing.mp4").path, dir.appending(path: "o.mp4").path],
                                     duration: nil) { _ in }
            XCTFail("expected a failure")
        } catch let error as FFmpegError {
            XCTAssertNotEqual(error.status, 0)
            XCTAssertFalse(error.log.isEmpty)
        }
    }

    func testCancellationStopsFFmpegQuickly() async throws {
        let ffmpeg = try Fixtures.ffmpeg()
        let dir = try Fixtures.directory(for: self)
        let output = dir.appending(path: "long.mp4")
        let task = Task {
            try await ffmpeg.convert(["-f", "lavfi", "-i", "testsrc2=duration=600:size=1920x1080:rate=30",
                                      "-c:v", "libx264", "-preset", "veryslow", output.path], duration: 600) { _ in }
        }
        try await Task.sleep(for: .milliseconds(500))

        let start = Date()
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
```

- [ ] **Step 3 : vérifier l'échec** — `scripts/test.sh` → `type 'MediaProbe' not found`, `value of type 'FFmpegRunner' has no member 'probe'`.

- [ ] **Step 4 : implémenter** — `App/Operations/Engines/FFmpegRunner.swift` :

```swift
import Foundation

/// What ffprobe reports about a media file.
struct MediaProbe: Equatable, Sendable {
    var duration: Double?
    /// Codec of the first real video stream (cover art excluded), e.g. "h264".
    var videoCodec: String?
    var audioCodec: String?

    /// Parses `ffprobe -show_entries format=duration:stream=codec_type,codec_name:stream_disposition=attached_pic -of json`.
    static func parse(_ json: Data) throws -> MediaProbe {
        struct Output: Decodable {
            struct Stream: Decodable {
                let codecType: String?
                let codecName: String?
                let disposition: [String: Int]?
            }
            struct Format: Decodable {
                let duration: String?
            }
            let streams: [Stream]?
            let format: Format?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(Output.self, from: json)
        let streams = output.streams ?? []
        func firstCodec(_ type: String) -> String? {
            streams.first { $0.codecType == type && $0.disposition?["attached_pic"] != 1 }?.codecName
        }
        let duration = output.format?.duration.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        return MediaProbe(duration: duration, videoCodec: firstCodec("video"), audioCodec: firstCodec("audio"))
    }
}

/// ffmpeg or ffprobe exited with an error; `log` is the end of its stderr.
struct FFmpegError: Error, CustomStringConvertible {
    let status: Int32
    let log: String
    var description: String { "exit \(status): \(log)" }
}

/// Runs the embedded ffmpeg / ffprobe (§3): duration from ffprobe, progress
/// from `-progress pipe:1`, cancellation by terminating the process.
struct FFmpegRunner: Sendable {
    let ffmpeg: URL
    let ffprobe: URL

    /// Binaries copied into Contents/Resources/bin by the "Embed ffmpeg" build phase.
    static var bundled: FFmpegRunner? {
        guard let bin = Bundle.main.resourceURL?.appending(path: "bin") else { return nil }
        let runner = FFmpegRunner(ffmpeg: bin.appending(path: "ffmpeg"), ffprobe: bin.appending(path: "ffprobe"))
        return runner.isAvailable ? runner : nil
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpeg.path)
            && FileManager.default.isExecutableFile(atPath: ffprobe.path)
    }

    func probe(_ input: URL) async throws -> MediaProbe {
        let result = try await Self.execute(ffprobe, [
            "-v", "error",
            "-show_entries", "format=duration:stream=codec_type,codec_name:stream_disposition=attached_pic",
            "-of", "json", input.path,
        ])
        guard result.status == 0 else { throw FFmpegError(status: result.status, log: result.log) }
        return try MediaProbe.parse(result.output)
    }

    /// Runs ffmpeg with `arguments` (input, codecs, output path). Progress is
    /// reported against `duration` when it is known.
    func convert(_ arguments: [String], duration: Double?,
                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let prefix = "out_time_us="
        let base = ["-hide_banner", "-nostdin", "-nostats", "-loglevel", "error", "-progress", "pipe:1", "-y"]
        let result = try await Self.execute(ffmpeg, base + arguments) { line in
            guard let duration, duration > 0, line.hasPrefix(prefix),
                  let microseconds = Double(line.dropFirst(prefix.count)) else { return }
            progress(min(max(microseconds / (duration * 1_000_000), 0), 1))
        }
        guard result.status == 0 else { throw FFmpegError(status: result.status, log: result.log) }
    }

    // MARK: Process

    private struct Result {
        let status: Int32
        let output: Data
        let log: String
    }

    /// Lets the cancellation handler reach the process.
    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
    }

    /// Launches `executable` and waits for it. Cancelling the task terminates it.
    private static func execute(_ executable: URL, _ arguments: [String],
                                onLine: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        let box = ProcessBox()
        let process = box.process
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let collector = OutputCollector(onLine: onLine)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collector.appendOutput(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collector.appendLog(data) }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                // Cancelled before the process existed: the handler could not stop it.
                if Task.isCancelled { process.terminate() }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }

        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        collector.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
        collector.appendLog(errors.fileHandleForReading.readDataToEndOfFile())
        try Task.checkCancellation()
        return Result(status: process.terminationStatus, output: collector.output, log: collector.log)
    }
}

/// Accumulates a process's output from pipe callbacks on background threads.
private final class OutputCollector: @unchecked Sendable {
    /// Only the end of stderr is kept, for the technical log.
    private static let maxLogBytes = 16_384

    private let lock = NSLock()
    private let onLine: (@Sendable (String) -> Void)?
    private var stdout = Data()
    private var pendingLine = Data()
    private var stderr = Data()

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    var output: Data { lock.withLock { stdout } }
    var log: String { lock.withLock { String(decoding: stderr, as: UTF8.self) } }

    func appendOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [String] = lock.withLock {
            stdout.append(data)
            pendingLine.append(data)
            var lines: [String] = []
            while let newline = pendingLine.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: pendingLine[pendingLine.startIndex..<newline], as: UTF8.self))
                pendingLine.removeSubrange(pendingLine.startIndex...newline)
            }
            return lines
        }
        if let onLine { lines.forEach(onLine) }
    }

    func appendLog(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            stderr.append(data)
            if stderr.count > Self.maxLogBytes { stderr = stderr.suffix(Self.maxLogBytes) }
        }
    }
}
```

- [ ] **Step 5 : lancer les tests** — `scripts/test.sh` → `TESTS OK`. Si le test d'annulation échoue ou bloque : systematic-debugging (vérifier d'abord si `terminate()` est bien appelé, puis la fermeture des pipes).
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 4: FFmpegRunner with probe, progress and cancellation"`.

---

### Task 4 : formats médias, opérations audio/vidéo et WebP, registre

**Files :**
- Create : `App/Operations/Converters/MediaOutput.swift`, `App/Operations/Converters/MediaConvertOperation.swift`, `App/Operations/Converters/ImageToWebPOperation.swift`
- Modify : `App/Operations/OperationRegistry.swift`
- Create : `Tests/OperationTests/MediaOutputTests.swift`, `Tests/OperationTests/MediaConvertOperationTests.swift`
- Replace : `Tests/OperationTests/OperationRegistryTests.swift`

**Interfaces :**
- Consumes : `FFmpegRunner`, `MediaProbe`, `FFmpegError`, `OperationContext.ffmpeg`, `OutputLocator.commitAsync`, `ImageConverter.uprightImage/write`, `FileTypes`.
- Produces : `MediaOutput` (`mp4, mov, gif, mp3, m4a, wav, flac`), `codecArguments(for:allowStreamCopy:) throws -> [String]`, `isVideo`, `isSameFormat(as:)` ; `MediaConvertOperation(output:)` ; `ImageToWebPOperation()` ; registre ordonné JPG, PNG, HEIC, WebP, TIFF, PDF, MP4, MOV, GIF, MP3, M4A, WAV, FLAC.

- [ ] **Step 1 : tests des arguments** — `Tests/OperationTests/MediaOutputTests.swift` :

```swift
import XCTest

final class MediaOutputTests: XCTestCase {
    private let h264AAC = MediaProbe(duration: 10, videoCodec: "h264", audioCodec: "aac")
    private let hevcPCM = MediaProbe(duration: 10, videoCodec: "hevc", audioCodec: "pcm_s16le")
    private let audioOnly = MediaProbe(duration: 10, videoCodec: nil, audioCodec: "mp3")
    private let silentVideo = MediaProbe(duration: 10, videoCodec: "h264", audioCodec: nil)

    private func has(_ arguments: [String], _ sequence: [String]) -> Bool {
        arguments.indices.contains { Array(arguments[$0...].prefix(sequence.count)) == sequence }
    }

    func testH264WithAACIsRewrappedWithoutReencoding() throws {
        let arguments = try MediaOutput.mp4.codecArguments(for: h264AAC, allowStreamCopy: true)
        XCTAssertTrue(has(arguments, ["-c:v", "copy"]))
        XCTAssertTrue(has(arguments, ["-c:a", "copy"]))
        XCTAssertTrue(has(arguments, ["-movflags", "+faststart"]))
    }

    func testOtherCodecsAreReencodedWithVideoToolbox() throws {
        for probe in [hevcPCM, h264AAC] {
            let arguments = try MediaOutput.mov.codecArguments(for: probe, allowStreamCopy: probe == hevcPCM)
            XCTAssertTrue(has(arguments, ["-c:v", "h264_videotoolbox", "-q:v", MediaOutput.videoQuality]))
            XCTAssertTrue(has(arguments, ["-c:a", "aac_at", "-b:a", "192k"]))
            XCTAssertFalse(arguments.contains("-movflags"), "faststart is for MP4 only")
        }
    }

    func testGIFUsesAPaletteAt15FPSAndAtMost720Wide() throws {
        let arguments = try MediaOutput.gif.codecArguments(for: h264AAC, allowStreamCopy: true)
        let filter = try XCTUnwrap(arguments.firstIndex(of: "-vf").map { arguments[$0 + 1] })
        XCTAssertTrue(filter.contains("fps=15"))
        XCTAssertTrue(filter.contains("min(720,iw)"))
        XCTAssertTrue(filter.contains("palettegen"))
        XCTAssertTrue(filter.contains("paletteuse"))
        XCTAssertTrue(arguments.contains("-an"))
    }

    func testAudioOutputs() throws {
        XCTAssertTrue(has(try MediaOutput.mp3.codecArguments(for: h264AAC, allowStreamCopy: true),
                          ["-c:a", "libmp3lame", "-b:a", "192k"]))
        XCTAssertTrue(has(try MediaOutput.m4a.codecArguments(for: h264AAC, allowStreamCopy: true), ["-c:a", "copy"]))
        XCTAssertTrue(has(try MediaOutput.m4a.codecArguments(for: audioOnly, allowStreamCopy: true),
                          ["-c:a", "aac_at", "-b:a", "256k"]))
        XCTAssertTrue(has(try MediaOutput.wav.codecArguments(for: audioOnly, allowStreamCopy: true), ["-c:a", "pcm_s16le"]))
        XCTAssertTrue(has(try MediaOutput.flac.codecArguments(for: audioOnly, allowStreamCopy: true), ["-c:a", "flac"]))
        XCTAssertTrue(has(try MediaOutput.mp3.codecArguments(for: audioOnly, allowStreamCopy: true), ["-map", "0:a:0", "-vn"]))
    }

    func testMissingStreamsGiveHumanErrors() {
        XCTAssertThrowsError(try MediaOutput.mp3.codecArguments(for: silentVideo, allowStreamCopy: true)) {
            XCTAssertEqual($0 as? OperationError, .noAudio)
        }
        for output in [MediaOutput.mp4, .gif] {
            XCTAssertThrowsError(try output.codecArguments(for: audioOnly, allowStreamCopy: true)) {
                XCTAssertEqual($0 as? OperationError, .noVideo)
            }
        }
    }
}
```

`Tests/OperationTests/MediaConvertOperationTests.swift` :

```swift
import XCTest

final class MediaConvertOperationTests: XCTestCase {
    private func context(_ dir: URL) throws -> OperationContext {
        OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: "out"))),
                         stripsLocation: false, ffmpeg: try Fixtures.ffmpeg())
    }

    private func convert(_ input: URL, to output: MediaOutput, in dir: URL) async throws -> URL {
        let outputs = try await MediaConvertOperation(output: output).run(inputs: [input], context: try context(dir)) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    func testHEVCBecomesH264InMP4() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mov", in: dir, codec: "hevc_videotoolbox")

        let output = try await convert(input, to: .mp4, in: dir)

        XCTAssertEqual(output.lastPathComponent, "clip.mp4")
        XCTAssertEqual(try Fixtures.codecs(of: output), ["h264", "aac"])
    }

    func testH264IsRewrappedIntoMOV() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir)

        let output = try await convert(input, to: .mov, in: dir)

        XCTAssertEqual(try Fixtures.codecs(of: output), ["h264", "aac"])
    }

    func testVideoToGIFIsAtMost720Wide() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("clip.mp4", in: dir, size: "1280x720")

        let output = try await convert(input, to: .gif, in: dir)

        XCTAssertEqual(try Fixtures.codecs(of: output), ["gif"])
        XCTAssertEqual(try Fixtures.info(output).width, 720)
    }

    func testSoundtrackAndAudioConversions() async throws {
        let dir = try Fixtures.directory(for: self)
        let video = try Fixtures.writeVideo("clip.mp4", in: dir)
        let wav = try Fixtures.writeAudio("tone.wav", in: dir)

        let mp3 = try await convert(video, to: .mp3, in: dir)
        let m4a = try await convert(video, to: .m4a, in: dir)
        let flac = try await convert(wav, to: .flac, in: dir)
        let backToWAV = try await convert(flac, to: .wav, in: dir)

        XCTAssertEqual(try Fixtures.codecs(of: mp3), ["mp3"])
        XCTAssertEqual(try Fixtures.codecs(of: m4a), ["aac"])
        XCTAssertEqual(try Fixtures.codecs(of: flac), ["flac"])
        XCTAssertEqual(try Fixtures.codecs(of: backToWAV), ["pcm_s16le"])
    }

    func testSilentVideoToMP3FailsWithAHumanMessage() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeVideo("silent.mp4", in: dir, audio: false)

        do {
            _ = try await convert(input, to: .mp3, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .noAudio)
        }
    }

    func testCorruptVideoFailsWithAHumanMessageAndADetail() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = dir.appending(path: "bad.mp4")
        try Data("not a video".utf8).write(to: input)

        do {
            _ = try await convert(input, to: .mov, in: dir)
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .unreadableVideo)
            XCTAssertNotNil(error.detail)
        }
    }

    func testMissingEngineIsReported() async throws {
        let dir = try Fixtures.directory(for: self)
        let context = OperationContext(output: OutputLocator(destination: .custom(dir)), stripsLocation: false)

        do {
            _ = try await MediaConvertOperation(output: .mp3).run(inputs: [dir.appending(path: "a.wav")], context: context) { _ in }
            XCTFail("expected an error")
        } catch let error as OperationError {
            XCTAssertEqual(error, .engineMissing)
        }
    }

    func testImageToWebP() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeImage("logo.png", in: dir, type: .png, alpha: true)

        let outputs = try await ImageToWebPOperation().run(inputs: [input], context: try context(dir)) { _ in }

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["logo.webp"])
        let info = try Fixtures.info(outputs[0])
        XCTAssertEqual(info.type, "org.webmproject.webp")
        XCTAssertEqual([info.width, info.height], [40, 20])
    }
}
```

Remplacer `Tests/OperationTests/OperationRegistryTests.swift` par :

```swift
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

    func testToolsAndActionsArriveInPhase5() {
        XCTAssertEqual(ids(["a.png"], .tools), [])
        XCTAssertEqual(ids(["a.mp4"], .actions), [])
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
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'MediaOutput' in scope`.

- [ ] **Step 3 : implémenter** — `App/Operations/Converters/MediaOutput.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// Audio and video outputs, encoded by the embedded ffmpeg (§5.4).
enum MediaOutput: String, CaseIterable, Sendable {
    case mp4, mov, gif, mp3, m4a, wav, flac

    /// h264_videotoolbox constant quality (1–100): clean picture, sensible size.
    static let videoQuality = "65"
    static let gifFrameRate = 15
    static let gifMaxWidth = 720

    var fileExtension: String { rawValue }
    var title: String { rawValue.uppercased() }

    var symbol: String {
        switch self {
        case .mp4: "film"
        case .mov: "film.stack"
        case .gif: "rectangle.stack"
        case .mp3, .m4a: "music.note"
        case .wav, .flac: "waveform"
        }
    }

    /// Inputs accepted, as in §5.4: videos give MP4, MOV, GIF, MP3, M4A;
    /// audio files give MP3, M4A, WAV, FLAC.
    var acceptsVideo: Bool {
        switch self {
        case .mp4, .mov, .gif, .mp3, .m4a: true
        case .wav, .flac: false
        }
    }

    var acceptsAudio: Bool {
        switch self {
        case .mp3, .m4a, .wav, .flac: true
        case .mp4, .mov, .gif: false
        }
    }

    /// Whether `input` already has this format (§5.4: no X → X).
    func isSameFormat(as input: UTType) -> Bool {
        let types: [UTType] = switch self {
        case .mp4: [.mpeg4Movie]
        case .mov: [.quickTimeMovie]
        case .gif: [.gif]
        case .mp3: [.mp3]
        case .m4a: [.mpeg4Audio, FileTypes.m4a]
        case .wav: [.wav]
        case .flac: [FileTypes.flac]
        }
        return types.contains { input.conforms(to: $0) }
    }

    /// ffmpeg arguments between the input and the output file, chosen from
    /// what ffprobe found. `allowStreamCopy` rewraps streams that already
    /// have the target codec instead of re-encoding them (instant, lossless).
    func codecArguments(for probe: MediaProbe, allowStreamCopy: Bool) throws -> [String] {
        switch self {
        case .mp4, .mov:
            guard let video = probe.videoCodec else { throw OperationError.noVideo }
            var arguments = ["-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn"]
            arguments += allowStreamCopy && video == "h264"
                ? ["-c:v", "copy"]
                : ["-c:v", "h264_videotoolbox", "-q:v", Self.videoQuality, "-pix_fmt", "yuv420p"]
            arguments += allowStreamCopy && probe.audioCodec == "aac"
                ? ["-c:a", "copy"]
                : ["-c:a", "aac_at", "-b:a", "192k"]
            // Finder and QuickTime only preview H.264 tagged avc1.
            arguments += ["-tag:v", "avc1"]
            if self == .mp4 {
                arguments += ["-movflags", "+faststart"]
            }
            return arguments
        case .gif:
            guard probe.videoCodec != nil else { throw OperationError.noVideo }
            let filter = "fps=\(Self.gifFrameRate),scale='min(\(Self.gifMaxWidth),iw)':-1:flags=lanczos,"
                + "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
            return ["-map", "0:v:0", "-an", "-vf", filter, "-loop", "0"]
        case .mp3, .m4a, .wav, .flac:
            guard let audio = probe.audioCodec else { throw OperationError.noAudio }
            let codec: [String] = switch self {
            case .mp3: ["-c:a", "libmp3lame", "-b:a", "192k", "-id3v2_version", "3"]
            case .m4a: allowStreamCopy && audio == "aac" ? ["-c:a", "copy"] : ["-c:a", "aac_at", "-b:a", "256k"]
            case .wav: ["-c:a", "pcm_s16le"]
            default: ["-c:a", "flac"]
            }
            return ["-map", "0:a:0", "-vn"] + codec
        }
    }
}
```

`App/Operations/Converters/MediaConvertOperation.swift` :

```swift
import Foundation
import UniformTypeIdentifiers

/// "To <format>" for audio and video, through the embedded ffmpeg (§5.4).
struct MediaConvertOperation: FileOperation {
    let output: MediaOutput

    var id: String { "convert.\(output.fileExtension)" }
    var kind: WheelMode { .convert }
    var title: String { output.title }
    var symbol: String { output.symbol }
    var usesMediaEngine: Bool { true }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { type in
            let accepted = FileTypes.isVideo(type) ? output.acceptsVideo : FileTypes.isAudio(type) && output.acceptsAudio
            guard accepted else { return false }
            return !output.isSameFormat(as: type)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { progress((Double(index) + $0) / Double(inputs.count)) }
            outputs.append(try await convert(input, with: ffmpeg, context: context, progress: share))
            share(1)
        }
        return outputs
    }

    private func convert(_ input: URL, with ffmpeg: FFmpegRunner, context: OperationContext,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let unreadable: OperationError = FileTypes.isVideo(FileTypes.type(of: input)) ? .unreadableVideo : .unreadableAudio
        let probe: MediaProbe
        do {
            probe = try await ffmpeg.probe(input)
        } catch let error as FFmpegError {
            throw unreadable.withDetail(error.description)
        }
        let rewrap = try output.codecArguments(for: probe, allowStreamCopy: true)
        let reencode = try output.codecArguments(for: probe, allowStreamCopy: false)

        return try await context.output.commitAsync(baseName: input.baseName, fileExtension: output.fileExtension,
                                                    for: input) { temporary in
            let arguments = { (codec: [String]) in ["-i", input.path] + codec + [temporary.path] }
            do {
                try await ffmpeg.convert(arguments(rewrap), duration: probe.duration, progress: progress)
            } catch let error as FFmpegError {
                // A stream copy can fail on unusual sources: retry with a full re-encode.
                guard rewrap != reencode else { throw unreadable.withDetail(error.description) }
                do {
                    try await ffmpeg.convert(arguments(reencode), duration: probe.duration, progress: progress)
                } catch let error as FFmpegError {
                    throw unreadable.withDetail(error.description)
                }
            }
        }
    }
}
```

`App/Operations/Converters/ImageToWebPOperation.swift` :

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// "WebP": ImageIO cannot encode WebP, so the upright image goes through a
/// temporary PNG and the embedded ffmpeg's libwebp (§3). Metadata is not kept.
struct ImageToWebPOperation: FileOperation {
    static let quality = "90"

    let id = "convert.webp"
    let kind = WheelMode.convert
    let title = "WebP"
    let symbol = "globe"

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { FileTypes.isImage($0) && !$0.conforms(to: .webP) }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let ffmpeg = context.ffmpeg else { throw OperationError.engineMissing }
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                  let image = ImageConverter.uprightImage(from: source) else {
                throw OperationError.unreadableImage
            }
            let png = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: png) }
            try ImageConverter.write(image, as: .png, to: png)

            outputs.append(try await context.output.commitAsync(baseName: input.baseName, fileExtension: "webp",
                                                                for: input) { temporary in
                do {
                    try await ffmpeg.convert(["-i", png.path, "-c:v", "libwebp", "-quality", Self.quality, temporary.path],
                                             duration: nil) { _ in }
                } catch let error as FFmpegError {
                    throw OperationError.writeFailed.withDetail(error.description)
                }
            })
            progress(Double(index + 1) / Double(inputs.count))
        }
        return outputs
    }
}
```

Dans `App/Operations/OperationRegistry.swift`, remplacer `standard` par :

```swift
    static let standard = OperationRegistry(operations: [
        ConvertToImageOperation(format: .jpeg, acceptsPDF: true),
        ConvertToImageOperation(format: .png, acceptsPDF: true),
        ConvertToImageOperation(format: .heic, acceptsPDF: false),
        ImageToWebPOperation(),
        ConvertToImageOperation(format: .tiff, acceptsPDF: false),
        ImagesToPDFOperation(),
    ] + MediaOutput.allCases.map { MediaConvertOperation(output: $0) as any FileOperation })
```

- [ ] **Step 4 : lancer les tests** — `scripts/test.sh` → `TESTS OK`. Si `a.m4a` est vu comme vidéo (conformance à `public.mpeg-4`), corriger `FileTypes.isVideo` pour exclure l'audio, avec un test qui le prouve d'abord.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 4: audio, video, GIF and WebP conversions"`.

---

### Task 5 : file d'exécution médias, annulation à la fermeture, essai réel

**Files :**
- Create : `App/Output/AsyncSemaphore.swift`, `Tests/OutputLocatorTests/AsyncSemaphoreTests.swift`
- Modify : `project.yml` (sources de test), `App/Output/JobQueue.swift`, `App/GestureCoordinator.swift`, `App/AppDelegate.swift`

**Interfaces :**
- Produces : `actor AsyncSemaphore(value:)`, `wait() async throws`, `signal()` ; `JobQueue.cancelAll()` ; `GestureCoordinator.cancelAllJobs()`.

- [ ] **Step 1 : tests** — ajouter `      - App/Output/AsyncSemaphore.swift` aux sources de `PivotTests` dans `project.yml` (après avoir créé le fichier vide), puis `Tests/OutputLocatorTests/AsyncSemaphoreTests.swift` :

```swift
import XCTest

final class AsyncSemaphoreTests: XCTestCase {
    func testAWaiterBeyondTheLimitWaitsForASignal() async throws {
        let semaphore = AsyncSemaphore(value: 2)
        try await semaphore.wait()
        try await semaphore.wait()
        let third = Task { () -> Date in
            try await semaphore.wait()
            return Date()
        }
        try await Task.sleep(for: .milliseconds(100))

        let released = Date()
        await semaphore.signal()

        let acquired = try await third.value
        XCTAssertGreaterThanOrEqual(acquired, released)
    }

    func testACancelledWaiterLeavesTheQueue() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        try await semaphore.wait()
        let waiter = Task { try await semaphore.wait() }
        try await Task.sleep(for: .milliseconds(50))

        waiter.cancel()

        do {
            try await waiter.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        // The cancelled waiter did not take the slot released next.
        await semaphore.signal()
        try await semaphore.wait()
    }
}
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'AsyncSemaphore' in scope`.

- [ ] **Step 3 : implémenter** — `App/Output/AsyncSemaphore.swift` :

```swift
import Foundation

/// Counting semaphore for async tasks. A waiter cancelled while queued
/// leaves the queue with a CancellationError and takes no slot.
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(value: Int) {
        available = value
    }

    func wait() async throws {
        if available > 0 {
            available -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
```

`App/Output/JobQueue.swift` : remplacer la déclaration de classe jusqu'à la fin de `run(_:inputs:)` par :

```swift
/// Runs operations off the main thread and reports through the HUD (§5.6).
/// New jobs never block: image jobs start at once, audio/video jobs wait
/// for one of `maxConcurrentMediaJobs` ffmpeg slots.
@MainActor
final class JobQueue {
    private static let maxConcurrentMediaJobs = 2
    /// Played through the system sound server: NSSound sets up a full audio
    /// session, which makes macOS check microphone and capture permissions.
    private static let completionSound: SystemSoundID = {
        var sound: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff") as CFURL, &sound)
        return sound
    }()
    private static let genericFailure = "La conversion a échoué."

    private let hud = HUDController()
    private let mediaSlots = AsyncSemaphore(value: JobQueue.maxConcurrentMediaJobs)
    private let ffmpeg = FFmpegRunner.bundled
    private var running: [UUID: Task<Void, Never>] = [:]

    init() {
        if ffmpeg == nil {
            AppInfo.jobLog.error("Embedded ffmpeg not found in the app bundle")
        }
    }

    func run(_ operation: any FileOperation, inputs: [URL]) {
        let id = UUID()
        let context = OperationContext(output: OutputLocator(destination: SettingsStore.outputDestination),
                                       stripsLocation: SettingsStore.stripsLocation, ffmpeg: ffmpeg)
        let toast = hud.begin(title: operation.title, symbol: operation.symbol) { [weak self] in
            self?.running[id]?.cancel()
        }
        let slots = operation.usesMediaEngine ? mediaSlots : nil
        AppInfo.jobLog.info("Job \(operation.id, privacy: .public) queued on \(inputs.count) file(s)")

        running[id] = Task.detached(priority: .userInitiated) {
            let result: Result<[URL], Error>
            do {
                try await slots?.wait()
                let outcome: Result<[URL], Error>
                do {
                    outcome = .success(try await operation.run(inputs: inputs, context: context) { fraction in
                        Task { @MainActor in toast.setProgress(fraction) }
                    })
                } catch {
                    outcome = .failure(error)
                }
                await slots?.signal()
                result = outcome
            } catch {
                // Cancelled while waiting for a slot.
                result = .failure(error)
            }
            await MainActor.run {
                self.finish(id, operation: operation, inputs: inputs, toast: toast, result: result)
            }
        }
    }

    /// Stops every job, terminating their ffmpeg processes (app quitting).
    func cancelAll() {
        running.values.forEach { $0.cancel() }
    }
```

(`finish(_:operation:inputs:toast:result:)` reste identique ; vérifier que `import AudioToolbox` est toujours en tête.)

Dans `App/GestureCoordinator.swift`, après `runOperation(_:on:)` :

```swift
    /// Called when the app quits, so no ffmpeg keeps running orphaned.
    func cancelAllJobs() {
        jobs.cancelAll()
    }
```

Dans `App/AppDelegate.swift`, avant `applicationShouldTerminateAfterLastWindowClosed` :

```swift
    func applicationWillTerminate(_ notification: Notification) {
        gestures.cancelAllJobs()
    }
```

- [ ] **Step 4 : tests + build** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK` sans avertissement.

- [ ] **Step 5 : essai réel** —

```bash
S=<scratchpad>; F=Vendor/ffmpeg/ffmpeg; APP=build/Build/Products/Debug/Pivot.app
$F -hide_banner -loglevel error -f lavfi -i testsrc2=duration=5:size=1920x1080:rate=30 -f lavfi -i sine=duration=5 -c:v hevc_videotoolbox -c:a aac -shortest "$S/essai pivot.mov"
for op in convert.mp4 convert.gif convert.mp3; do pkill -x Pivot; open -n -g "$APP" --args -debugRun $op -debugFiles "(\"$S/essai pivot.mov\")"; sleep 8; done
for f in ~/Downloads/Convertis/essai\ pivot*; do echo "$f → $(Vendor/ffmpeg/ffprobe -v error -show_entries stream=codec_name -of csv=p=0 "$f" | tr '\n' ' ')"; done
/usr/bin/log show --last 2m --info --predicate 'subsystem == "local.pivot.app" AND category == "jobs"' --style compact
pgrep -x ffmpeg || echo "aucun ffmpeg restant"
```

Attendu : `essai pivot.mp4` (h264 aac), `.gif` (gif), `.mp3` (mp3) ; logs « queued » puis « done » ; aucun ffmpeg restant. Puis annulation à la fermeture : lancer `-debugRun convert.mp4` sur une vidéo longue (60 s, 4K), `pkill -x Pivot` après 1 s → `pgrep -x ffmpeg` vide. Supprimer les fichiers d'essai de `Convertis`.

- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 4: media job slots and cancel on quit"`.

---

### Task 6 : vérification finale et documentation

**Files :** Modify : `CLAUDE.md`, `README.md`

- [ ] **Step 1 : vérification** (superpowers:verification-before-completion) — `scripts/test.sh` (nombre de tests, 0 échec), `scripts/build.sh Debug`, `codesign --verify --deep --strict` sur l'app, relecture des « Contraintes globales » ligne par ligne.
- [ ] **Step 2 : invites de confidentialité** — lancer une conversion vidéo par `-debugRun` et lister les requêtes `tccd` de Pivot **et** de ffmpeg (`eventMessage CONTAINS "pid=<PID>"` pour chacun) ; noter tout service inattendu (micro, capture…) et le traiter avant de résumer.
- [ ] **Step 3 : CLAUDE.md** — ligne de phase 4 → 🟡 avec l'état réel ; ajouter `scripts/fetch-ffmpeg.sh` aux commandes. README : mention de `scripts/fetch-ffmpeg.sh` (appelé automatiquement par `build.sh`).
- [ ] **Step 4 : commit + push**.
- [ ] **Step 5 : résumé à Raphaël** avec la checklist manuelle : vidéo iPhone (HEVC) → MP4, MOV, GIF, MP3, M4A ; MKV/WebM → MP4 ; WAV → MP3/M4A/FLAC ; image → WebP ; 3 vidéos d'un coup (2 en parallèle, la 3ᵉ attend) ; grosse vidéo (≥ 2 Go) → barre de progression puis annulation (fichier partiel absent, ffmpeg arrêté dans le Moniteur d'activité) ; quitter Pivot pendant une conversion ; vidéo sans son → MP3 (message clair) ; drop depuis le Bureau sans invite.
