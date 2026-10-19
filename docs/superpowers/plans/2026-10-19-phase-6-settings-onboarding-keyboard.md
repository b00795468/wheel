# Phase 6 — Onboarding, permissions, Réglages complets, mode clavier — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Ce projet impose `superpowers:executing-plans` (voir CLAUDE.md, section Skills).

**Goal :** au premier lancement, un onboarding de 3 écrans explique le geste, fait accorder les autorisations et choisir le dossier de sortie ; les Réglages couvrent tout le §5.7 ; un raccourci global ouvre la roue sur la sélection du Finder, pilotable au clavier.

**Architecture :** les réglages vivent dans `SettingsStore` (UserDefaults typés, injectable en test) : `TriggerMapping` (touche → roue, toujours distinctes), `KeyCombo` (raccourci), `OutputQuality`, destination, son, localisation. Un `SettingsModel` (ObservableObject) relie la fenêtre SwiftUI au store et rafraîchit l'état des autorisations tant que la fenêtre est ouverte. Le raccourci passe par Carbon `RegisterEventHotKey` (aucune autorisation) ; la sélection du Finder par AppleScript (autorisation Automatisation) ; la roue en mode clavier est un panneau non activant qui devient « key » sans activer Pivot.

**Tech stack :** Swift 5, SwiftUI (Form, TimelineView), AppKit, Carbon HIToolbox (raccourci global), ServiceManagement (`SMAppService.mainApp`), NSAppleScript / `AEDeterminePermissionToAutomateTarget`, XCTest.

**Spec :** `SPEC.md` (§5.1 touches remappables, §5.3 mode clavier, §5.7 réglages/onboarding/permissions, §3 Info.plist, §9 phase 6).

## Contraintes globales

- Touches remappables (Shift / Command / Control / Option) pour chacune des 3 roues (§5.1).
- Raccourci global configurable, défaut **⌃⌥Espace** ; sélection du Finder via AppleScript (permission Automatisation) ; roue au centre de l'écran actif ; ←/→ (ou ↑/↓) pour naviguer, **Entrée** pour appliquer, **Échap** pour annuler, ⇧/⌘/⌃ pour changer de roue (§5.3).
- La rouvrir ouvre les Réglages ; onboarding au premier lancement, SwiftUI, **3 écrans max** : 1. le geste en animation simple ; 2. permissions, état en direct (✓ / à faire), bouton vers le bon panneau, détection automatique ; 3. dossier de sortie + « Ouvrir au démarrage » coché par défaut via `SMAppService.mainApp` (§5.7).
- Réglages : touches des 3 roues, raccourci, dossier de sortie, ouvrir au démarrage, son, retrait de la localisation, qualité par défaut (Standard / Haute), état des permissions, « Quitter l'application », version (§5.7).
- `Info.plist` : `NSAppleEventsUsageDescription` en français (§3).
- Aucun impact CPU au repos : un rafraîchissement périodique n'est permis que fenêtre ouverte ou autorisation manquante (§7).
- Ne jamais voler le focus avec la roue du geste ; ne jamais lire un fichier avant l'action.
- Interface en français ; code et commentaires en anglais ; zéro package externe.

**Écart signalé (§1.5) :** la SPEC liste « Surveillance de l'entrée ». Mesuré : en 6 h de journaux, Pivot n'a jamais déclenché `kTCCServiceListenEvent` et le geste a été validé avec la seule Accessibilité ; le raccourci Carbon n'exige rien. On ne demande donc **que l'Accessibilité** (obligatoire) et le **contrôle du Finder** (facultatif, pour le mode clavier).

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `App/DragMonitor/ModifierTapDetector.swift` | `TriggerKey` devient `String`/`Codable`, gagne `name` |
| `App/Wheel/WheelModel.swift` | `TriggerMapping` (remplace `WheelMode.trigger`), `WheelModel.step` |
| `App/Settings/KeyCombo.swift` (nouveau) | Raccourci : code de touche, modificateurs, affichage, Carbon |
| `App/Settings/SettingsStore.swift` | Tous les réglages en lecture/écriture, `defaults` injectable |
| `App/Operations/FileOperation.swift` | `OutputQuality`, `OperationContext.quality` |
| Opérations (`ConvertToImageOperation`, `ImageToWebPOperation`, `MediaOutput`, `MediaConvertOperation`, `ResizeOperation`), `JobQueue` | Qualité par défaut appliquée |
| `App/Permissions/PermissionsManager.swift` | État Accessibilité / Automatisation, panneaux Réglages Système |
| `App/Settings/LoginItem.swift` (nouveau) | « Ouvrir au démarrage » |
| `App/Keyboard/HotKeyCenter.swift`, `App/Keyboard/FinderSelection.swift` (nouveaux) | Raccourci global, sélection du Finder |
| `App/Wheel/WheelPanel.swift`, `App/Wheel/WheelController.swift`, `App/Wheel/WheelView.swift` | Mode clavier, indices de touches remappées |
| `App/GestureCoordinator.swift` | Touches remappées, raccourci, surveillance de l'Accessibilité |
| `App/Feedback/HUDToast.swift`, `App/Output/JobQueue.swift` | Pastille d'information |
| `App/Settings/SettingsModel.swift`, `SettingsView.swift`, `ShortcutRecorder.swift`, `PermissionRow.swift`, `SettingsWindowController.swift` | Fenêtre Réglages |
| `App/Settings/OnboardingView.swift`, `GestureAnimationView.swift`, `OnboardingWindowController.swift` (nouveaux) | Onboarding |
| `App/AppDelegate.swift`, `App/Info.plist` | Premier lancement, usage AppleScript |
| `Tests/SettingsTests/*` (nouveau dossier) | Store, mapping, raccourci, sélection Finder |

---

### Task 1 : modèle des réglages (touches, raccourci, store)

**Files :**
- Modify : `App/DragMonitor/ModifierTapDetector.swift`, `App/Wheel/WheelModel.swift`, `App/Wheel/WheelView.swift`, `App/Wheel/WheelController.swift`, `App/GestureCoordinator.swift`, `App/Settings/SettingsStore.swift`, `App/Operations/FileOperation.swift`, `App/AppDelegate.swift`, `project.yml`, `Tests/GestureTests/WheelModelTests.swift`
- Create : `App/Settings/KeyCombo.swift`, `Tests/SettingsTests/SettingsTests.swift`

**Interfaces :**
- Produces : `TriggerKey: String, Codable` + `name` ; `TriggerMapping` (`standard`, `key(for:)`, `mode(for:)`, `assigning(_:to:)`) ; `KeyCombo(keyCode:modifiers:keyLabel:)`, `.standard`, `isValid`, `display`, `carbonModifiers`, `KeyCombo.label(keyCode:characters:)` ; `OutputQuality` (`standard`, `high`, `title`, `imageQuality`, `webPQuality`, `videoQuality`) ; `SettingsStore.defaults` (settable), `hasCompletedOnboarding`, `outputDestination { get set }`, `customOutputFolder`, `stripsLocation { get set }`, `playsCompletionSound { get set }`, `outputQuality`, `triggers`, `hotKey`, `SettingsStore.hotKeyDidChange` ; `WheelTitleView.setMode(_:title:triggers:)`.

- [ ] **Step 1 : sources de test** — dans `project.yml`, sources de `PivotTests`, ajouter `      - App/Settings/SettingsStore.swift` et `      - App/Settings/KeyCombo.swift` (créer d'abord `App/Settings/KeyCombo.swift` vide).

- [ ] **Step 2 : tests** — `Tests/SettingsTests/SettingsTests.swift` :

```swift
import AppKit
import Carbon.HIToolbox
import XCTest

final class SettingsTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "PivotTests-\(UUID().uuidString)"
        SettingsStore.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        SettingsStore.defaults = .standard
        super.tearDown()
    }

    func testDefaults() {
        XCTAssertEqual(SettingsStore.triggers, .standard)
        XCTAssertEqual(SettingsStore.hotKey, .standard)
        XCTAssertEqual(SettingsStore.outputQuality, .standard)
        XCTAssertEqual(SettingsStore.outputDestination, .convertedFolder)
        XCTAssertTrue(SettingsStore.playsCompletionSound)
        XCTAssertFalse(SettingsStore.stripsLocation)
        XCTAssertFalse(SettingsStore.hasCompletedOnboarding)
    }

    func testEverySettingRoundTrips() {
        let triggers = TriggerMapping.standard.assigning(.option, to: .actions)
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift], keyLabel: "K")
        SettingsStore.triggers = triggers
        SettingsStore.hotKey = combo
        SettingsStore.outputQuality = .high
        SettingsStore.playsCompletionSound = false
        SettingsStore.stripsLocation = true
        SettingsStore.hasCompletedOnboarding = true

        XCTAssertEqual(SettingsStore.triggers, triggers)
        XCTAssertEqual(SettingsStore.hotKey, combo)
        XCTAssertEqual(SettingsStore.outputQuality, .high)
        XCTAssertFalse(SettingsStore.playsCompletionSound)
        XCTAssertTrue(SettingsStore.stripsLocation)
        XCTAssertTrue(SettingsStore.hasCompletedOnboarding)
    }

    func testCustomFolderIsRememberedWhenSwitchingBack() {
        let folder = URL(fileURLWithPath: "/Users/x/Exports", isDirectory: true)
        SettingsStore.outputDestination = .custom(folder)
        XCTAssertEqual(SettingsStore.outputDestination, .custom(folder))

        SettingsStore.outputDestination = .besideOriginal

        XCTAssertEqual(SettingsStore.outputDestination, .besideOriginal)
        XCTAssertEqual(SettingsStore.customOutputFolder?.path, folder.path)
    }

    func testChangingTheShortcutIsAnnounced() {
        expectation(forNotification: SettingsStore.hotKeyDidChange, object: nil)
        SettingsStore.hotKey = KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.control, .option], keyLabel: "P")
        waitForExpectations(timeout: 1)
    }

    func testTriggerMappingKeepsKeysDistinct() {
        let standard = TriggerMapping.standard
        XCTAssertEqual(standard.mode(for: .shift), .convert)
        XCTAssertEqual(standard.mode(for: .command), .tools)
        XCTAssertEqual(standard.mode(for: .control), .actions)
        XCTAssertNil(standard.mode(for: .option))

        let swapped = standard.assigning(.command, to: .convert)
        XCTAssertEqual(swapped.key(for: .convert), .command)
        XCTAssertEqual(swapped.key(for: .tools), .shift, "the wheel that had ⌘ takes the old key")

        let option = standard.assigning(.option, to: .actions)
        XCTAssertEqual([option.convert, option.tools, option.actions], [.shift, .command, .option])
    }

    func testKeyCombo() throws {
        XCTAssertEqual(KeyCombo.standard.display, "⌃⌥Espace")
        XCTAssertEqual(KeyCombo.standard.carbonModifiers, UInt32(controlKey | optionKey))
        XCTAssertTrue(KeyCombo.standard.isValid)
        XCTAssertFalse(KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.shift], keyLabel: "K").isValid)
        XCTAssertEqual(KeyCombo(keyCode: 0, modifiers: [.command, .capsLock], keyLabel: "A").modifiers, [.command])
        XCTAssertEqual(KeyCombo.label(keyCode: UInt16(kVK_Space), characters: " "), "Espace")
        XCTAssertEqual(KeyCombo.label(keyCode: UInt16(kVK_ANSI_K), characters: "k"), "K")
        let data = try JSONEncoder().encode(KeyCombo.standard)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), .standard)
    }
}
```

Dans `Tests/GestureTests/WheelModelTests.swift`, supprimer `testDefaultTriggersMapToDistinctModes` (remplacé par `testTriggerMappingKeepsKeysDistinct`).

- [ ] **Step 3 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'TriggerMapping' in scope`, `KeyCombo`…

- [ ] **Step 4 : implémenter** — `ModifierTapDetector.swift` : `enum TriggerKey: CaseIterable {` devient `enum TriggerKey: String, CaseIterable, Codable, Sendable {`, et après `glyph` :

```swift
    /// Label in Settings.
    var name: String {
        switch self {
        case .shift: "⇧ Maj"
        case .command: "⌘ Commande"
        case .control: "⌃ Contrôle"
        case .option: "⌥ Option"
        }
    }
```

`WheelModel.swift` : dans `WheelMode`, supprimer `var trigger` (et son commentaire) et `static func mode(for:)` ; ajouter après l'enum `WheelMode` :

```swift
/// Which modifier opens which wheel (§5.1). Remappable in Settings; the
/// three keys always stay distinct.
struct TriggerMapping: Equatable, Codable, Sendable {
    var convert = TriggerKey.shift
    var tools = TriggerKey.command
    var actions = TriggerKey.control

    static let standard = TriggerMapping()

    func key(for mode: WheelMode) -> TriggerKey {
        switch mode {
        case .convert: convert
        case .tools: tools
        case .actions: actions
        }
    }

    func mode(for key: TriggerKey) -> WheelMode? {
        WheelMode.allCases.first { self.key(for: $0) == key }
    }

    /// Gives `key` to `mode`; the wheel that had `key` takes `mode`'s old key.
    func assigning(_ key: TriggerKey, to mode: WheelMode) -> TriggerMapping {
        var mapping = self
        if let other = self.mode(for: key), other != mode {
            mapping.set(self.key(for: mode), for: other)
        }
        mapping.set(key, for: mode)
        return mapping
    }

    private mutating func set(_ key: TriggerKey, for mode: WheelMode) {
        switch mode {
        case .convert: convert = key
        case .tools: tools = key
        case .actions: actions = key
        }
    }
}
```

`App/Settings/KeyCombo.swift` :

```swift
import AppKit
import Carbon.HIToolbox

/// The keyboard-mode shortcut (§5.3): a key with at least one of ⌘ ⌃ ⌥.
struct KeyCombo: Equatable, Codable, Sendable {
    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// ⌃⌥Espace (§5.3).
    static let standard = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.control, .option], keyLabel: "Espace")

    let keyCode: UInt16
    /// NSEvent.ModifierFlags raw value, limited to `allowedModifiers`.
    let modifierFlags: UInt
    /// What the key shows, captured when recorded ("Espace", "K"…).
    let keyLabel: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.allowedModifiers).rawValue
        self.keyLabel = keyLabel
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// ⌘, ⌃ or ⌥ is required so that plain typing never triggers it.
    var isValid: Bool { !modifiers.intersection([.command, .control, .option]).isEmpty }

    /// "⌃⌥Espace", modifiers in the macOS menu order ⌃ ⌥ ⇧ ⌘.
    var display: String {
        let glyphs: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    /// Label of a recorded key: a name for keys without a printable character.
    static func label(keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Espace"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: (characters ?? "").uppercased()
        }
    }
}
```

`App/Operations/FileOperation.swift`, avant `struct OperationContext` :

```swift
/// "Qualité par défaut" (§5.7) for conversions. Compression keeps its own
/// fixed settings (§5.4).
enum OutputQuality: String, CaseIterable, Sendable {
    case standard, high

    var title: String {
        switch self {
        case .standard: "Standard"
        case .high: "Haute"
        }
    }

    /// JPEG, HEIC and AVIF encoder quality.
    var imageQuality: Double { self == .standard ? 0.9 : 0.97 }
    var webPQuality: Int { self == .standard ? 90 : 97 }
    /// h264_videotoolbox constant quality (1–100).
    var videoQuality: String { self == .standard ? "65" : "80" }
}
```

`App/Settings/SettingsStore.swift` devient :

```swift
import Foundation

/// Typed access to UserDefaults. Keys live here and nowhere else.
enum SettingsStore {
    private enum Key {
        /// Name kept from phase 1, when it only marked the first launch.
        static let hasCompletedOnboarding = "hasCompletedFirstLaunch"
        static let outputDestination = "outputDestination"
        static let customOutputFolder = "customOutputFolder"
        static let stripsLocation = "stripsLocation"
        static let playsCompletionSound = "playsCompletionSound"
        static let outputQuality = "outputQuality"
        static let triggers = "triggers"
        static let hotKey = "hotKey"
    }

    /// Stored values of `Key.outputDestination`.
    private enum DestinationValue {
        static let converted = "converted"
        static let besideOriginal = "besideOriginal"
        static let custom = "custom"
    }

    /// Posted when the keyboard shortcut changes, so it gets registered again.
    static let hotKeyDidChange = Notification.Name("PivotHotKeyDidChange")

    /// A private suite in tests.
    static var defaults: UserDefaults = .standard

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    static var outputDestination: OutputDestination {
        get {
            switch defaults.string(forKey: Key.outputDestination) {
            case DestinationValue.besideOriginal:
                return .besideOriginal
            case DestinationValue.custom:
                return customOutputFolder.map(OutputDestination.custom) ?? .convertedFolder
            default:
                return .convertedFolder
            }
        }
        set {
            switch newValue {
            case .convertedFolder:
                defaults.set(DestinationValue.converted, forKey: Key.outputDestination)
            case .besideOriginal:
                defaults.set(DestinationValue.besideOriginal, forKey: Key.outputDestination)
            case .custom(let folder):
                defaults.set(DestinationValue.custom, forKey: Key.outputDestination)
                defaults.set(folder.path, forKey: Key.customOutputFolder)
            }
        }
    }

    /// Last folder picked, kept while another destination is selected.
    static var customOutputFolder: URL? {
        defaults.string(forKey: Key.customOutputFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// "Retirer les données de localisation", off by default (§5.5).
    static var stripsLocation: Bool {
        get { defaults.bool(forKey: Key.stripsLocation) }
        set { defaults.set(newValue, forKey: Key.stripsLocation) }
    }

    /// Discreet sound when a job finishes, on by default (§5.6).
    static var playsCompletionSound: Bool {
        // bool(forKey:) also understands "NO"/"0" strings (launch arguments).
        get { defaults.object(forKey: Key.playsCompletionSound) == nil ? true : defaults.bool(forKey: Key.playsCompletionSound) }
        set { defaults.set(newValue, forKey: Key.playsCompletionSound) }
    }

    static var outputQuality: OutputQuality {
        get { defaults.string(forKey: Key.outputQuality).flatMap(OutputQuality.init) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: Key.outputQuality) }
    }

    static var triggers: TriggerMapping {
        get { decode(TriggerMapping.self, forKey: Key.triggers) ?? .standard }
        set { encode(newValue, forKey: Key.triggers) }
    }

    static var hotKey: KeyCombo {
        get { decode(KeyCombo.self, forKey: Key.hotKey) ?? .standard }
        set {
            encode(newValue, forKey: Key.hotKey)
            NotificationCenter.default.post(name: hotKeyDidChange, object: nil)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
```

Adapter les appelants :
  - `App/AppDelegate.swift` : `SettingsStore.hasCompletedFirstLaunch` → `SettingsStore.hasCompletedOnboarding` (deux occurrences) ;
  - `App/GestureCoordinator.swift` : `WheelMode.mode(for: key)` → `SettingsStore.triggers.mode(for: key)` ;
  - `App/Wheel/WheelView.swift`, `WheelTitleView` : `func setMode(_ mode: WheelMode, title: String? = nil) {` devient `func setMode(_ mode: WheelMode, title: String? = nil, triggers: TriggerMapping = .standard) {` et `other.trigger.glyph` devient `triggers.key(for: other).glyph` ;
  - `App/Wheel/WheelController.swift`, `reloadItems()` : `titleView.setMode(model.mode, title: model.title)` devient `titleView.setMode(model.mode, title: model.title, triggers: SettingsStore.triggers)`.

- [ ] **Step 5 : lancer les tests + build** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK`.
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 6: settings model (remappable keys, shortcut, store)"`.

---

### Task 2 : qualité par défaut appliquée aux conversions

**Files :**
- Modify : `App/Operations/FileOperation.swift`, `App/Operations/Converters/ConvertToImageOperation.swift`, `App/Operations/Converters/ImageToWebPOperation.swift`, `App/Operations/Converters/MediaOutput.swift`, `App/Operations/Converters/MediaConvertOperation.swift`, `App/Operations/Tools/ResizeOperation.swift`, `App/Output/JobQueue.swift`, `Tests/OperationTests/MediaOutputTests.swift`, `Tests/OperationTests/ConvertOperationTests.swift`

**Interfaces :**
- Consumes : `OutputQuality`.
- Produces : `OperationContext.quality` (défaut `.standard`) ; `MediaOutput.codecArguments(for:allowStreamCopy:quality:)` (`quality` défaut `.standard`) ; `MediaOutput.videoQuality` supprimé.

- [ ] **Step 1 : tests** — dans `MediaOutputTests`, remplacer `MediaOutput.videoQuality` par `OutputQuality.standard.videoQuality`, et ajouter :

```swift
    func testHighQualityRaisesTheVideoQuality() throws {
        let arguments = try MediaOutput.mp4.codecArguments(for: hevcPCM, allowStreamCopy: true, quality: .high)
        XCTAssertTrue(has(arguments, ["-q:v", OutputQuality.high.videoQuality]))
        XCTAssertEqual(OutputQuality.high.videoQuality, "80")
    }
```

Ajouter à `ConvertOperationTests` :

```swift
    func testHighQualityGivesALargerJPEG() async throws {
        let dir = try Fixtures.directory(for: self)
        let input = try Fixtures.writeNoiseImage("noise.png", in: dir, type: .png)
        func convert(_ quality: OutputQuality) async throws -> Int {
            let context = OperationContext(output: OutputLocator(destination: .custom(dir.appending(path: quality.rawValue))),
                                           stripsLocation: false, quality: quality)
            let output = try await ConvertToImageOperation(format: .jpeg, acceptsPDF: true)
                .run(inputs: [input], context: context) { _ in }[0]
            return try XCTUnwrap(output.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }

        let standard = try await convert(.standard)
        let high = try await convert(.high)

        XCTAssertGreaterThan(high, standard)
    }
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `extra argument 'quality'`.

- [ ] **Step 3 : implémenter** —
  - `OperationContext` : après `var ffmpeg: FFmpegRunner? = nil`, ajouter `/// Encoder quality of conversions ("Qualité par défaut").` puis `var quality: OutputQuality = .standard` ;
  - `ConvertToImageOperation.run` : en tête de la fonction, `let format = self.format.withQuality(context.quality.imageQuality)` (les usages suivants de `format` dans `run` prennent cette version) ;
  - `ImageToWebPOperation` : supprimer `static let quality = 90` ; `quality: Self.quality` devient `quality: context.quality.webPQuality` ;
  - `MediaOutput` : supprimer `static let videoQuality = "65"` et son commentaire ; signature `func codecArguments(for probe: MediaProbe, allowStreamCopy: Bool, quality: OutputQuality = .standard) throws -> [String]` ; `"-q:v", Self.videoQuality` devient `"-q:v", quality.videoQuality` ;
  - `MediaConvertOperation.convert` : les deux appels `output.codecArguments(for: probe, allowStreamCopy: …)` reçoivent `, quality: context.quality` ;
  - `ResizeOperation` : `"-q:v", MediaOutput.videoQuality` devient `"-q:v", context.quality.videoQuality` ; dans `resizeImage`, `quality: nil` devient `quality: context.quality.imageQuality` ;
  - `JobQueue.run` : le contexte reçoit `quality: SettingsStore.outputQuality` :

```swift
        let context = OperationContext(output: OutputLocator(destination: SettingsStore.outputDestination),
                                       stripsLocation: SettingsStore.stripsLocation, ffmpeg: ffmpeg,
                                       quality: SettingsStore.outputQuality)
```

- [ ] **Step 4 : tests + build** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK`.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 6: default quality setting applied to conversions"`.

---

### Task 3 : services système (autorisations, démarrage, raccourci, sélection Finder)

**Files :**
- Modify : `App/Permissions/PermissionsManager.swift`, `App/GestureCoordinator.swift`, `App/Info.plist`, `project.yml`
- Create : `App/Settings/LoginItem.swift`, `App/Keyboard/HotKeyCenter.swift`, `App/Keyboard/FinderSelection.swift`, `Tests/SettingsTests/FinderSelectionTests.swift`

**Interfaces :**
- Produces : `PermissionsManager.Status { granted, denied, notDetermined }`, `isAccessibilityTrusted`, `grantAccessibility()`, `openAccessibilitySettings()`, `openAutomationSettings()`, `finderAutomationStatus()` ; `LoginItem.isEnabled`, `needsApproval`, `setEnabled(_:)` ; `HotKeyCenter.register(_:) -> Bool`, `unregister()`, `onPress` ; `FinderSelection.current() async -> Result<[URL], FinderSelection.Failure>`, `FinderSelection.parse(_:)`, `Failure.notAuthorized`, `Failure.unavailable(String)`.

- [ ] **Step 1 : tests** — ajouter `      - App/Keyboard/FinderSelection.swift` aux sources de `PivotTests` (après avoir créé le fichier vide), puis `Tests/SettingsTests/FinderSelectionTests.swift` :

```swift
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
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `cannot find 'FinderSelection' in scope`.

- [ ] **Step 3 : implémenter** — `App/Keyboard/FinderSelection.swift` :

```swift
import Foundation

/// Files selected in the Finder, read through AppleScript (§5.3). The first
/// call makes macOS ask whether Pivot may control the Finder (Automation).
enum FinderSelection {
    enum Failure: Error, Equatable {
        case notAuthorized
        case unavailable(String)
    }

    /// AppleScript error "not authorized to send Apple events".
    private static let notAuthorizedError = -1743

    private static let source = """
    tell application "Finder"
        set selectedItems to selection as alias list
        set paths to {}
        repeat with selectedItem in selectedItems
            set end of paths to POSIX path of selectedItem
        end repeat
        return paths
    end tell
    """

    /// Runs off the main thread: the first call waits for the user's answer.
    static func current() async -> Result<[URL], Failure> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int
                    continuation.resume(returning: .failure(code == notAuthorizedError
                        ? .notAuthorized : .unavailable(error.description)))
                } else {
                    continuation.resume(returning: .success(parse(result)))
                }
            }
        }
    }

    /// POSIX paths from the script's list; folders end with "/".
    static func parse(_ descriptor: NSAppleEventDescriptor?) -> [URL] {
        guard let descriptor, descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0)?.stringValue }
            .map { URL(fileURLWithPath: $0, isDirectory: $0.hasSuffix("/")) }
    }
}
```

`App/Permissions/PermissionsManager.swift` devient :

```swift
import AppKit
import ApplicationServices

/// Permission states and shortcuts to the right System Settings panes (§5.7).
/// Only Accessibility is required: global key monitors and the Carbon
/// shortcut work without Input Monitoring (measured in phases 2 to 5).
enum PermissionsManager {
    enum Status {
        case granted, denied, notDetermined
    }

    private static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let automationPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    private static let finderBundleIdentifier = "com.apple.finder"

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt, which also adds Pivot to the Accessibility list.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Puts Pivot in the list, then opens the pane where it is switched on.
    static func grantAccessibility() {
        requestAccessibility()
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(accessibilityPane)
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(automationPane)
    }

    /// Whether Pivot may read the Finder selection, checked without asking.
    static func finderAutomationStatus() -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: finderBundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined
        }
    }
}
```

`App/Settings/LoginItem.swift` :

```swift
import ServiceManagement

/// "Ouvrir au démarrage" through SMAppService (§5.7).
enum LoginItem {
    static var isEnabled: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    /// macOS may want the user to approve it in System Settings › Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppInfo.log.error("Login item change to \(enabled, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

`App/Keyboard/HotKeyCenter.swift` :

```swift
import AppKit
import Carbon.HIToolbox

/// System-wide shortcut through Carbon's RegisterEventHotKey, which needs
/// no permission at all (§5.3).
@MainActor
final class HotKeyCenter {
    /// "PVTK": identifies Pivot's hot key among the app's Carbon events.
    private static let signature: OSType = 0x5056_544B

    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Returns false when another app already owns the shortcut.
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            AppInfo.log.error("Shortcut \(combo.display, privacy: .public) unavailable (\(status))")
        }
        return status == noErr
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let center = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { center.onPress?() }
            return noErr
        }, 1, &spec, center, &handler)
    }
}
```

`App/Info.plist`, avant `<key>NSPrincipalClass</key>` :

```xml
	<key>NSAppleEventsUsageDescription</key>
	<string>Pivot lit les fichiers sélectionnés dans le Finder pour ouvrir la roue avec le raccourci clavier.</string>
```

`App/GestureCoordinator.swift` : ajouter les propriétés

```swift
    /// Accessibility is polled at this pace only while it is missing.
    private static let accessibilityPollInterval: TimeInterval = 2
    private var accessibilityTimer: Timer?
```

remplacer dans `start()` le bloc `keyMonitor = NSEvent.addGlobalMonitorForEvents(…) { … }` par :

```swift
        installKeyMonitor()
        watchAccessibilityUntilGranted()
```

et ajouter les méthodes :

```swift
    private func installKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        }
    }

    /// Key monitors added before Accessibility is granted can stay deaf, so
    /// the monitor is installed again once it is (§5.7 "détection automatique").
    private func watchAccessibilityUntilGranted() {
        guard !PermissionsManager.isAccessibilityTrusted else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: Self.accessibilityPollInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard PermissionsManager.isAccessibilityTrusted else { return }
                timer.invalidate()
                self?.installKeyMonitor()
                AppInfo.log.info("Accessibility granted: key monitor installed again")
            }
        }
    }
```

- [ ] **Step 4 : tests + build** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK` ; `plutil -extract NSAppleEventsUsageDescription raw build/Build/Products/Debug/Pivot.app/Contents/Info.plist` → la phrase.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 6: permissions, login item, global shortcut, Finder selection"`.

---

### Task 4 : mode clavier

**Files :**
- Modify : `App/Wheel/WheelModel.swift`, `App/Wheel/WheelPanel.swift`, `App/Wheel/WheelController.swift`, `App/GestureCoordinator.swift`, `App/Feedback/HUDToast.swift`, `App/Output/JobQueue.swift`, `Tests/GestureTests/WheelModelTests.swift`

**Interfaces :**
- Consumes : `HotKeyCenter`, `FinderSelection`, `SettingsStore.hotKey`, `SettingsStore.hotKeyDidChange`, `SettingsStore.triggers`.
- Produces : `WheelModel.step(from:count:forward:)` ; `WheelPanel.acceptsKeyboard`, `keyHandler`, `onResignKey` ; `WheelController.showForKeyboard(_:files:)` ; `HUDController.inform(_:symbol:)`, `JobQueue.inform(_:symbol:)`.

- [ ] **Step 1 : tests** — ajouter à `WheelModelTests` :

```swift
    func testArrowStepsWrapAround() {
        XCTAssertEqual(WheelModel.step(from: nil, count: 4, forward: true), 0)
        XCTAssertEqual(WheelModel.step(from: nil, count: 4, forward: false), 3)
        XCTAssertEqual(WheelModel.step(from: 3, count: 4, forward: true), 0)
        XCTAssertEqual(WheelModel.step(from: 0, count: 4, forward: false), 3)
        XCTAssertEqual(WheelModel.step(from: 1, count: 4, forward: true), 2)
        XCTAssertNil(WheelModel.step(from: nil, count: 0, forward: true))
    }
```

- [ ] **Step 2 : vérifier l'échec** — `scripts/test.sh` → `type 'WheelModel' has no member 'step'`.

- [ ] **Step 3 : implémenter** — à la fin de `WheelModel.swift` :

```swift
extension WheelModel {
    /// Slot reached by an arrow key (§5.3): clockwise when `forward`, wrapping.
    static func step(from slot: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let slot else { return forward ? 0 : count - 1 }
        return (slot + (forward ? 1 : count - 1)) % count
    }
}
```

`App/Wheel/WheelPanel.swift` : remplacer `override var canBecomeKey: Bool { false }` par :

```swift
    /// Keyboard mode (§5.3): the panel takes key events without activating
    /// Pivot, as a non-activating panel may. Never during a drag.
    var acceptsKeyboard = false
    /// Returns true when it handled the key or modifier event.
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboard }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        if keyHandler?(event) != true { super.flagsChanged(with: event) }
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
```

et mettre à jour le commentaire de la classe : `/// It only becomes key in keyboard mode, so the frontmost app keeps focus (§5.2).`

`App/Wheel/WheelController.swift` :
  - propriétés, après `private var generation = 0` :

```swift
    /// Opened by the shortcut rather than a drag (§5.3).
    private var keyboardMode = false
    private var keyboardTapDetector = ModifierTapDetector()

    private enum KeyCode {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let escape: UInt16 = 53
    }
```

  - à la fin de `init()` :

```swift
        panel.keyHandler = { [weak self] event in self?.handleKeyboard(event) ?? false }
        panel.onResignKey = { [weak self] in
            guard let self, self.keyboardMode else { return }
            self.dismiss(reason: "keyboard wheel lost focus")
        }
```

  - après `switchMode(to:)` :

```swift
    /// Keyboard mode: the wheel opens at the centre of the screen under the
    /// cursor, with the first slot highlighted.
    func showForKeyboard(_ mode: WheelMode, files: [URL]) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let center = screen.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? mouse
        keyboardMode = true
        keyboardTapDetector = ModifierTapDetector()
        show(mode, files: files, at: center)
        panel.acceptsKeyboard = true
        panel.makeKey()
        highlightFirstSlot()
        AppInfo.gestureLog.info("Keyboard wheel shown, panel is key: \(self.panel.isKeyWindow, privacy: .public)")
    }

    private func highlightFirstSlot() {
        setHoveredSlot(WheelModel.step(from: nil, count: model?.items.count ?? 0, forward: true))
    }

    private func handleKeyboard(_ event: NSEvent) -> Bool {
        guard keyboardMode, isVisible else { return false }
        if event.type == .flagsChanged {
            if let key = keyboardTapDetector.flagsChanged(event.modifierFlags, at: event.timestamp),
               let mode = SettingsStore.triggers.mode(for: key) {
                switchMode(to: mode)
            }
            return true
        }
        keyboardTapDetector.otherKeyPressed()
        let count = model?.items.count ?? 0
        switch event.keyCode {
        case KeyCode.right, KeyCode.down:
            setHoveredSlot(WheelModel.step(from: hoveredSlot, count: count, forward: true))
        case KeyCode.left, KeyCode.up:
            setHoveredSlot(WheelModel.step(from: hoveredSlot, count: count, forward: false))
        case KeyCode.returnKey, KeyCode.enter:
            activateHoveredSlot()
        case KeyCode.escape:
            dismiss(reason: "Escape (keyboard)")
        default:
            break
        }
        return true
    }

    /// Return on a slot: navigate like a long hover, or apply the segment.
    private func activateHoveredSlot() {
        guard let slot = hoveredSlot, let model, model.items.indices.contains(slot) else { return }
        if let navigation = navigation(for: model.items[slot]) {
            navigate(navigation)
        } else if case .segment(let segment) = model.items[slot] {
            deliver(segment)
        }
    }

    /// Applies a leaf segment to the files, for a drop or a Return.
    private func deliver(_ segment: WheelSegment) {
        let paths = files.map(\.path).joined(separator: ", ")
        AppInfo.gestureLog.notice("Apply \(segment.id, privacy: .public): \(paths, privacy: .public)")
        let chosen = files
        dismiss(reason: "applied \(segment.id)")
        onDrop?(segment.id, chosen)
    }
```

  - dans `switchMode(to:)`, après `load(mode)`, ajouter `if keyboardMode { highlightFirstSlot() }` ;
  - dans `dismiss(reason:)`, après `setHoveredSlot(nil)`, ajouter :

```swift
        if keyboardMode {
            keyboardMode = false
            panel.acceptsKeyboard = false
        }
```

  - dans `setHoveredSlot(_:)`, la condition `if let navigation = navigation(for: model.items[slot]) {` devient `if !keyboardMode, let navigation = navigation(for: model.items[slot]) {` (au clavier on navigue avec Entrée) ;
  - dans `navigate(_:)`, après `reloadItems()`, ajouter `if keyboardMode { highlightFirstSlot() }` ;
  - dans `dropTarget(_:didDropAt:)`, remplacer les lignes depuis `let paths = …` jusqu'à `return true` par :

```swift
        deliver(segment)
        return true
```

`App/Feedback/HUDToast.swift`, dans `HUDController`, après `cancel(_:)` :

```swift
    /// A short notice that is not about a job (keyboard mode problems).
    func inform(_ message: String, symbol: String) {
        let toast = HUDToast(onCancel: {})
        toast.showSuccess(message: message, outputs: [], symbol: symbol)
        present(toast)
        remove(toast, after: Self.failureDuration)
    }
```

`App/Output/JobQueue.swift`, après `cancelAll()` :

```swift
    func inform(_ message: String, symbol: String) {
        hud.inform(message, symbol: symbol)
    }
```

`App/GestureCoordinator.swift` :
  - propriétés : `private let hotKeys = HotKeyCenter()` et `private var hotKeyObserver: NSObjectProtocol?` ;
  - à la fin de `start()` :

```swift
        hotKeys.onPress = { [weak self] in self?.openFromKeyboard() }
        hotKeys.register(SettingsStore.hotKey)
        hotKeyObserver = NotificationCenter.default.addObserver(forName: SettingsStore.hotKeyDidChange, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.hotKeys.register(SettingsStore.hotKey) }
        }
```

  - nouvelle méthode :

```swift
    /// The shortcut (§5.3): opens the wheel on the Finder selection.
    private func openFromKeyboard() {
        guard !wheel.isVisible else { return }
        Task { [weak self] in
            let selection = await FinderSelection.current()
            guard let self else { return }
            switch selection {
            case .success(let files) where !files.isEmpty:
                self.wheel.showForKeyboard(.convert, files: files)
            case .success:
                self.jobs.inform("Sélectionnez des fichiers dans le Finder.", symbol: "cursorarrow.rays")
            case .failure(.notAuthorized):
                self.jobs.inform("Autorisez Pivot à piloter le Finder.", symbol: "lock")
                PermissionsManager.openAutomationSettings()
            case .failure(.unavailable(let detail)):
                TechnicalLog.record("Finder selection failed: \(detail)")
                self.jobs.inform("Impossible de lire la sélection du Finder.", symbol: "exclamationmark.triangle")
            }
        }
    }
```

  - dans `performDebugLaunchArguments()`, avant `guard let name = defaults.string(forKey: "debugWheel")` :

```swift
        if defaults.bool(forKey: "debugKeyboard") {
            wheel.showForKeyboard(.convert, files: files)
            return
        }
```

et le commentaire de la fonction mentionne `-debugKeyboard YES -debugFiles '("/path")'` (roue clavier sans raccourci).

- [ ] **Step 4 : tests + build** — `scripts/test.sh` → `TESTS OK` ; `scripts/build.sh Debug` → `BUILD OK`.
- [ ] **Step 5 : essai réel** — `open -n -g $APP --args -debugKeyboard YES -debugFiles '("/tmp/a.png")'`, puis `osascript -e 'tell application "System Events" to key code 124'` (→), `key code 53` (Échap) ; le journal `gesture` doit montrer « Keyboard wheel shown, panel is key: true » puis « Wheel dismissed: Escape (keyboard) ». Si le panneau ne reçoit pas les touches, systematic-debugging avant tout changement (vérifier d'abord quelle fenêtre est « key » et quelle app est active).
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 6: keyboard mode on the Finder selection"`.

---

### Task 5 : fenêtre Réglages complète

**Files :**
- Create : `App/Settings/SettingsModel.swift`, `App/Settings/ShortcutRecorder.swift`, `App/Settings/PermissionRow.swift`
- Replace : `App/Settings/SettingsView.swift`
- Modify : `App/Settings/SettingsWindowController.swift`, `App/AppDelegate.swift`

**Interfaces :**
- Consumes : `SettingsStore`, `TriggerMapping`, `KeyCombo`, `OutputQuality`, `LoginItem`, `PermissionsManager`, `FinderSelection`.
- Produces : `SettingsModel` (`triggers`, `hotKey`, `destination`, `customFolder`, `quality`, `stripsLocation`, `playsSound`, `launchAtLogin`, `accessibilityGranted`, `finderAutomation`, `loginNeedsApproval`, `setTrigger(_:for:)`, `chooseCustomFolder()`, `startRefreshing()`, `stopRefreshing()`, `refreshPermissions()`, `requestFinderAutomation()`, `SettingsModel.Destination`) ; `PermissionRow(title:detail:status:action:)` ; `ShortcutRecorder(combo:)` ; `SettingsWindowController(model:)` ; debug `-debugSettingsSnapshot <png>`.

- [ ] **Step 1 : modèle** — `App/Settings/SettingsModel.swift` :

```swift
import AppKit
import Combine

/// State of the Settings and onboarding windows: reads SettingsStore, writes
/// every change back, and refreshes permission states while a window shows.
@MainActor
final class SettingsModel: ObservableObject {
    enum Destination: String, CaseIterable {
        case converted, beside, custom

        var title: String {
            switch self {
            case .converted: "Téléchargements › Convertis"
            case .beside: "À côté de l'original"
            case .custom: "Dossier personnalisé…"
            }
        }
    }

    private static let refreshInterval: TimeInterval = 1

    @Published var triggers = SettingsStore.triggers {
        didSet { SettingsStore.triggers = triggers }
    }
    @Published var hotKey = SettingsStore.hotKey {
        didSet { SettingsStore.hotKey = hotKey }
    }
    @Published var destination: Destination {
        didSet { applyDestination() }
    }
    @Published private(set) var customFolder = SettingsStore.customOutputFolder
    @Published var quality = SettingsStore.outputQuality {
        didSet { SettingsStore.outputQuality = quality }
    }
    @Published var stripsLocation = SettingsStore.stripsLocation {
        didSet { SettingsStore.stripsLocation = stripsLocation }
    }
    @Published var playsSound = SettingsStore.playsCompletionSound {
        didSet { SettingsStore.playsCompletionSound = playsSound }
    }
    @Published var launchAtLogin = LoginItem.isEnabled {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            LoginItem.setEnabled(launchAtLogin)
            refreshPermissions()
        }
    }
    @Published private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted
    @Published private(set) var finderAutomation = PermissionsManager.finderAutomationStatus()
    @Published private(set) var loginNeedsApproval = LoginItem.needsApproval

    private var timer: Timer?

    init() {
        destination = switch SettingsStore.outputDestination {
        case .convertedFolder: .converted
        case .besideOriginal: .beside
        case .custom: .custom
        }
    }

    func setTrigger(_ key: TriggerKey, for mode: WheelMode) {
        triggers = triggers.assigning(key, to: mode)
    }

    /// Folder picker; falls back to the previous destination when cancelled.
    func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else {
            if customFolder == nil { destination = .converted }
            return
        }
        customFolder = folder
        destination = .custom
    }

    private func applyDestination() {
        switch destination {
        case .converted:
            SettingsStore.outputDestination = .convertedFolder
        case .beside:
            SettingsStore.outputDestination = .besideOriginal
        case .custom:
            if let customFolder {
                SettingsStore.outputDestination = .custom(customFolder)
            } else {
                // Not from inside a SwiftUI update: the picker is modal.
                DispatchQueue.main.async { self.chooseCustomFolder() }
            }
        }
    }

    /// Live permission states (§5.7) while a window is open, never at rest.
    func startRefreshing() {
        refreshPermissions()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refreshPermissions() {
        accessibilityGranted = PermissionsManager.isAccessibilityTrusted
        finderAutomation = PermissionsManager.finderAutomationStatus()
        loginNeedsApproval = LoginItem.needsApproval
    }

    /// First request shows the macOS prompt; once refused, only Settings can change it.
    func requestFinderAutomation() {
        if finderAutomation == .denied {
            PermissionsManager.openAutomationSettings()
            return
        }
        Task {
            _ = await FinderSelection.current()
            refreshPermissions()
        }
    }
}
```

- [ ] **Step 2 : composants** — `App/Settings/PermissionRow.swift` :

```swift
import SwiftUI

/// One permission with its live state and a button to grant it (§5.7).
struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionsManager.Status
    let action: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(status == .granted ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Text("Autorisé").foregroundStyle(.secondary)
            } else {
                Button("Autoriser…", action: action)
            }
        }
    }
}
```

`App/Settings/ShortcutRecorder.swift` :

```swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then type the new shortcut (⌘, ⌃ or ⌥ required); Escape cancels.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.combo = combo
        button.onRecord = { combo = $0 }
    }
}

final class RecorderButton: NSButton {
    var onRecord: ((KeyCombo) -> Void)?
    var combo = KeyCombo.standard {
        didSet { refreshTitle() }
    }
    private var isRecording = false {
        didSet { refreshTitle() }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    // Shortcuts with ⌘ arrive as key equivalents, the others as key downs.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                 keyLabel: KeyCombo.label(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
        guard candidate.isValid else { return }
        isRecording = false
        onRecord?(candidate)
    }

    private func refreshTitle() {
        title = isRecording ? "Tapez le raccourci…" : combo.display
    }
}
```

- [ ] **Step 3 : vue** — `App/Settings/SettingsView.swift` devient :

```swift
import AppKit
import SwiftUI

/// The Settings window (§5.7), reached by opening the app again.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Roues") {
                    ForEach(WheelMode.allCases, id: \.self) { mode in
                        Picker(mode.title, selection: Binding(
                            get: { model.triggers.key(for: mode) },
                            set: { model.setTrigger($0, for: mode) }
                        )) {
                            ForEach(TriggerKey.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                }
                Section("Mode clavier") {
                    LabeledContent("Raccourci") {
                        ShortcutRecorder(combo: $model.hotKey).fixedSize()
                    }
                    Text("Ouvre la roue sur les fichiers sélectionnés dans le Finder : flèches pour choisir, Entrée pour appliquer, Échap pour annuler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Sortie") {
                    Picker("Dossier", selection: $model.destination) {
                        ForEach(SettingsModel.Destination.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if model.destination == .custom, let folder = model.customFolder {
                        LabeledContent("Emplacement") {
                            HStack {
                                Text(folder.path).lineLimit(1).truncationMode(.middle)
                                Button("Changer…") { model.chooseCustomFolder() }
                            }
                        }
                    }
                    Picker("Qualité par défaut", selection: $model.quality) {
                        ForEach(OutputQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Retirer les données de localisation", isOn: $model.stripsLocation)
                    Toggle("Son à la fin d'une conversion", isOn: $model.playsSound)
                }
                Section("Général") {
                    Toggle("Ouvrir au démarrage", isOn: $model.launchAtLogin)
                    if model.loginNeedsApproval {
                        Text("À approuver dans Réglages Système › Général › Ouverture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Autorisations") {
                    PermissionRow(title: "Accessibilité", detail: "Indispensable : détecte le geste.",
                                  status: model.accessibilityGranted ? .granted : .denied,
                                  action: PermissionsManager.grantAccessibility)
                    PermissionRow(title: "Contrôle du Finder", detail: "Facultatif : pour le raccourci clavier.",
                                  status: model.finderAutomation, action: model.requestFinderAutomation)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("\(AppInfo.name) \(AppInfo.version)").foregroundStyle(.secondary)
                Spacer()
                Button("Quitter \(AppInfo.name)") { NSApp.terminate(nil) }
            }
            .padding(16)
        }
        .frame(width: 520, height: 660)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }
}
```

`SettingsWindowController` : `convenience init()` devient `convenience init(model: SettingsModel)` et `NSHostingController(rootView: SettingsView())` devient `NSHostingController(rootView: SettingsView(model: model))`.

`AppDelegate` : ajouter `private let settings = SettingsModel()` et `private lazy var settingsWindow = SettingsWindowController()` devient `private lazy var settingsWindow = SettingsWindowController(model: settings)`. Ajouter au bloc DEBUG de `applicationDidFinishLaunching`, après `gestures.performDebugLaunchArguments()` :

```swift
        if let path = UserDefaults.standard.string(forKey: "debugSettingsSnapshot") {
            DebugSnapshot.render(SettingsView(model: settings), size: CGSize(width: 520, height: 660), to: path)
        }
```

et en fin de fichier :

```swift
#if DEBUG
/// Offscreen render of a SwiftUI view to a PNG, to check a window's layout
/// without screen capture rights.
@MainActor
enum DebugSnapshot {
    static func render<Content: View>(_ view: Content, size: CGSize, to path: String) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            window.close()
        }
    }
}
#endif
```

(`import SwiftUI` va en tête de `AppDelegate.swift`, pas dans le bloc `#if DEBUG`.)

- [ ] **Step 4 : build + rendu** — `scripts/build.sh Debug` → `BUILD OK` ; `scripts/test.sh` → `TESTS OK` ; `open -n -g $APP --args -debugSettingsSnapshot $S/settings.png` puis lire l'image : sections Roues, Mode clavier (⌃⌥Espace), Sortie, Général, Autorisations, pied avec version et Quitter.
- [ ] **Step 5 : commit** — `git add -A && git commit -m "Phase 6: complete Settings window"`.

(Ajusté à l'exécution : la section « Autorisations » passe en tête du formulaire, sinon elle était sous la ligne de flottaison dans une fenêtre de 660 pt.)

---

### Task 6 : onboarding (3 écrans) et premier lancement

**Files :**
- Create : `App/Settings/GestureAnimationView.swift`, `App/Settings/OnboardingView.swift`, `App/Settings/OnboardingWindowController.swift`
- Modify : `App/AppDelegate.swift`

**Interfaces :**
- Consumes : `SettingsModel`, `PermissionRow`, `LoginItem`, `SettingsStore.hasCompletedOnboarding`.
- Produces : `OnboardingView(model:page:onFinish:)` ; `OnboardingWindowController(model:onFinish:)` ; debug `-debugOnboardingSnapshot <png> -debugOnboardingPage <0|1|2>`.

- [ ] **Step 1 : animation** — `App/Settings/GestureAnimationView.swift` :

```swift
import SwiftUI

/// The gesture in a 4-second loop (§5.7, screen 1): a file slides in, a
/// key is tapped, the wheel opens around it with a segment lit, then fades.
/// With "Réduire les animations", a still frame of the open wheel.
struct GestureAnimationView: View {
    private static let loop: TimeInterval = 4
    private static let segments = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 2.2 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            frame(at: time)
        }
        .frame(width: 260, height: 180)
        .accessibilityLabel("Animation : glisser un fichier, taper une touche, déposer sur la roue")
    }

    private func frame(at time: TimeInterval) -> some View {
        let slide = min(time / 1, 1)
        let keyDown = (1.0..<1.3).contains(time)
        let wheel = time < 1.3 ? 0 : (time < 3.2 ? min((time - 1.3) / 0.15, 1) : max(1 - (time - 3.2) / 0.3, 0))
        return ZStack {
            ForEach(0..<Self.segments, id: \.self) { index in
                WheelSlice(index: index, count: Self.segments)
                    .fill(index == 1 && time > 2 ? Theme.accentColor : Color.secondary.opacity(0.25))
            }
            .frame(width: 150, height: 150)
            .scaleEffect(0.92 + 0.08 * wheel)
            .opacity(wheel)

            Image(systemName: "doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .offset(x: -110 * (1 - slide))

            Text("⇧")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(keyDown ? Theme.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)))
                .scaleEffect(keyDown ? 0.9 : 1)
                .offset(x: 105, y: 70)
        }
    }
}

/// One ring segment, clockwise from the top like the real wheel.
private struct WheelSlice: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.38
        let span = 360.0 / Double(count)
        let start = Angle.degrees(-90 - span / 2 + span * Double(index) + 1.5)
        let end = Angle.degrees(-90 + span / 2 + span * Double(index) - 1.5)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
```

Dans `App/Theme.swift`, ajouter `import SwiftUI` et :

```swift
    static let accentColor = Color(nsColor: accent)
```

- [ ] **Step 2 : écrans** — `App/Settings/OnboardingView.swift` :

```swift
import SwiftUI

/// First launch (§5.7): the gesture, the permissions, then where files go.
struct OnboardingView: View {
    private static let pageCount = 3

    @ObservedObject var model: SettingsModel
    @State var page = 0
    /// Not private: a private property would make the memberwise init private.
    @State var launchAtLogin = true
    /// Called with the "Ouvrir au démarrage" choice.
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: gesturePage
                case 1: permissionsPage
                default: outputPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 28)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<Self.pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Retour") { page -= 1 }
                }
                if page < Self.pageCount - 1 {
                    Button("Continuer") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Terminer") { onFinish(launchAtLogin) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 470)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }

    private var gesturePage: some View {
        VStack(spacing: 16) {
            GestureAnimationView()
            Text("Glisser, taper, déposer").font(.title2.weight(.semibold))
            Text("Commencez à glisser un fichier, tapez une touche : la roue s'ouvre autour du curseur. Lâchez le fichier sur une action.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ForEach(WheelMode.allCases, id: \.self) { mode in
                    HStack(spacing: 6) {
                        Text(model.triggers.key(for: mode).glyph).font(.headline)
                        Text(mode.title)
                    }
                }
            }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Autorisations").font(.title2.weight(.semibold))
            Text("macOS demande votre accord pour que \(AppInfo.name) voie le geste. L'état se met à jour tout seul.")
                .foregroundStyle(.secondary)
            PermissionRow(title: "Accessibilité", detail: "Indispensable : détecte la touche tapée pendant le glisser.",
                          status: model.accessibilityGranted ? .granted : .denied,
                          action: PermissionsManager.grantAccessibility)
            PermissionRow(title: "Contrôle du Finder", detail: "Facultatif : pour ouvrir la roue au clavier (\(model.hotKey.display)).",
                          status: model.finderAutomation, action: model.requestFinderAutomation)
            if !model.accessibilityGranted {
                Text("Sans l'Accessibilité, la roue ne peut pas s'ouvrir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var outputPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Où ranger les fichiers ?").font(.title2.weight(.semibold))
            Text("Les originaux ne sont jamais modifiés : chaque résultat est un nouveau fichier.")
                .foregroundStyle(.secondary)
            Picker("Dossier", selection: $model.destination) {
                ForEach(SettingsModel.Destination.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.destination == .custom, let folder = model.customFolder {
                Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Toggle("Ouvrir \(AppInfo.name) au démarrage", isOn: $launchAtLogin)
            Text("Pour retrouver les réglages plus tard, ouvrez \(AppInfo.name) à nouveau (Spotlight ou dossier Applications).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
```

`App/Settings/OnboardingWindowController.swift` :

```swift
import AppKit
import SwiftUI

/// Owns the onboarding window, shown until it is completed once.
@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init(model: SettingsModel, onFinish: @escaping (Bool) -> Void) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Bienvenue dans \(AppInfo.name)"
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model, onFinish: onFinish))
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3 : premier lancement** — dans `AppDelegate` :
  - ajouter `private lazy var onboardingWindow = OnboardingWindowController(model: settings) { [weak self] launchAtLogin in self?.finishOnboarding(launchAtLogin: launchAtLogin) }` ;
  - remplacer le bloc Accessibilité du début de `applicationDidFinishLaunching` (de `// Without Accessibility` jusqu'à la fin du `if !trusted { … }`) par :

```swift
        let trusted = PermissionsManager.isAccessibilityTrusted
        AppInfo.log.info("Accessibility trusted: \(trusted, privacy: .public)")
```

  - remplacer le bloc final « The app has no Dock… » par :

```swift
        // The app has no Dock or menu bar icon: the first launch shows the
        // onboarding (§5.7), later launches stay silent unless a permission is missing.
        if !SettingsStore.hasCompletedOnboarding {
            onboardingWindow.show()
        } else if !trusted {
            PermissionsManager.requestAccessibility()
        }
```

  - ajouter :

```swift
    private func finishOnboarding(launchAtLogin: Bool) {
        SettingsStore.hasCompletedOnboarding = true
        LoginItem.setEnabled(launchAtLogin)
        settings.refreshPermissions()
        onboardingWindow.close()
    }
```

  - dans le bloc DEBUG, après le rendu des Réglages :

```swift
        if let path = UserDefaults.standard.string(forKey: "debugOnboardingSnapshot") {
            let page = UserDefaults.standard.integer(forKey: "debugOnboardingPage")
            DebugSnapshot.render(OnboardingView(model: settings, page: page) { _ in },
                                 size: CGSize(width: 560, height: 470), to: path)
        }
```

- [ ] **Step 4 : build + rendus** — `scripts/build.sh Debug`, `scripts/test.sh` ; rendus des pages 0, 1, 2 (`-debugOnboardingSnapshot $S/onb-N.png -debugOnboardingPage N`) et lecture des images.
- [ ] **Step 5 : premier lancement réel** — sauvegarder la valeur courante (`defaults read local.pivot.app hasCompletedFirstLaunch`), la supprimer (`defaults delete local.pivot.app hasCompletedFirstLaunch`), lancer l'app : la fenêtre « Bienvenue dans Pivot » doit exister (`osascript … count windows`) ; quitter ; restaurer la valeur (`defaults write local.pivot.app hasCompletedFirstLaunch -bool YES`) pour ne pas imposer l'onboarding à Raphaël — il le testera lui-même via la checklist. Ne pas cliquer « Terminer » (cela modifierait ses éléments d'ouverture).
- [ ] **Step 6 : commit** — `git add -A && git commit -m "Phase 6: onboarding on first launch"`.

---

### Task 7 : vérification finale et documentation

- [ ] **Step 1 : vérification** (superpowers:verification-before-completion) — tests complets, build, `codesign --verify --deep --strict`, CPU au repos (`top -l 3 -s 5 -pid …` → 0,0 % et 0 réveil) avec l'app lancée normalement, contraintes globales relues ligne par ligne.
- [ ] **Step 2 : CLAUDE.md** — ligne de phase 6 → 🟡 avec l'état réel ; écart « Surveillance de l'entrée » ; nouveaux arguments debug (`-debugKeyboard`, `-debugSettingsSnapshot`, `-debugOnboardingSnapshot`).
- [ ] **Step 3 : commit + push**.
- [ ] **Step 4 : résumé à Raphaël** avec la checklist : onboarding complet (supprimer `hasCompletedFirstLaunch` pour le revoir), animation, autorisation Accessibilité détectée sans relancer, contrôle du Finder, dossier personnalisé, « Ouvrir au démarrage » (Réglages Système › Ouverture), remapper ⌥ sur Outils puis vérifier le geste et l'indice dans le titre, changer le raccourci, ⌃⌥Espace sur une sélection Finder → flèches, Entrée, Échap, ⇧/⌘/⌃, Qualité Haute (JPG plus lourd), son désactivé, « Retirer la localisation ».
