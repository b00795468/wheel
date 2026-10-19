import AppKit
import XCTest

final class ModifierTapDetectorTests: XCTestCase {
    private var detector = ModifierTapDetector()

    private func flags(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) -> TriggerKey? {
        detector.flagsChanged(flags, at: time)
    }

    func testQuickPressAndReleaseIsATap() {
        XCTAssertNil(flags(.shift, at: 10.0))
        XCTAssertEqual(flags([], at: 10.15), .shift)
    }

    func testEachTriggerKeyIsRecognised() {
        for key in TriggerKey.allCases {
            XCTAssertNil(flags(key.flag, at: 1))
            XCTAssertEqual(flags([], at: 1.1), key)
        }
    }

    func testHoldingLongerThanTheLimitIsNotATap() {
        XCTAssertNil(flags(.command, at: 10.0))
        XCTAssertNil(flags([], at: 10.0 + ModifierTapDetector.maxTapDuration))
    }

    func testOtherKeyDuringPressCancelsTheTap() {
        XCTAssertNil(flags(.command, at: 10.0))
        detector.otherKeyPressed()
        XCTAssertNil(flags([], at: 10.1))
    }

    func testChordIsNotATap() {
        XCTAssertNil(flags(.command, at: 10.0))
        XCTAssertNil(flags([.command, .shift], at: 10.05))
        XCTAssertNil(flags(.command, at: 10.1))
        XCTAssertNil(flags([], at: 10.15))
    }

    /// ⌘ held (Finder's "move"), then shift tapped: not a clean tap of either.
    func testTapWhileAnotherModifierIsHeldIsIgnored() {
        XCTAssertNil(flags(.command, at: 10.0))
        XCTAssertNil(flags([.command, .shift], at: 11.0))
        XCTAssertNil(flags(.command, at: 11.1))
    }

    func testNonTriggerFlagsAreIgnored() {
        XCTAssertNil(flags([.shift, .capsLock, .numericPad], at: 10.0))
        XCTAssertEqual(flags([.capsLock], at: 10.1), .shift)
    }

    func testDetectorRecoversAfterAnAbortedTap() {
        XCTAssertNil(flags(.control, at: 10.0))
        XCTAssertNil(flags([], at: 11.0))
        XCTAssertNil(flags(.control, at: 12.0))
        XCTAssertEqual(flags([], at: 12.2), .control)
    }
}
