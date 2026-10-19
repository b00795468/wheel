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
