import XCTest
@testable import RoundelCore

final class RingInteractionTests: XCTestCase {
    // MARK: Hold-and-release

    func testHoldReleaseSelectsHighlightedOnKeyUp() {
        var ring = RingInteraction()
        XCTAssertEqual(ring.hotkeyDown(mode: .holdRelease), .opened)
        ring.pointerMoved(section: 2)
        XCTAssertEqual(ring.highlighted, 2)
        XCTAssertEqual(ring.hotkeyUp(), .select(2))
        XCTAssertFalse(ring.isOpen)
        XCTAssertNil(ring.highlighted)
    }

    func testHoldReleaseInDeadZoneDismisses() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .holdRelease)
        ring.pointerMoved(section: 1)
        ring.pointerMoved(section: nil)
        XCTAssertEqual(ring.hotkeyUp(), .dismiss)
        XCTAssertFalse(ring.isOpen)
    }

    func testHoldReleaseIgnoresClicks() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .holdRelease)
        ring.pointerMoved(section: 3)
        XCTAssertEqual(ring.click(section: 3), .none)
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(ring.click(section: nil), .none)
        XCTAssertTrue(ring.isOpen)
    }

    // MARK: Click-required

    func testClickRequiredIgnoresKeyUp() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .clickRequired)
        ring.pointerMoved(section: 4)
        XCTAssertEqual(ring.hotkeyUp(), .none)
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(ring.highlighted, 4)
    }

    func testClickRequiredSelectsClickedSection() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .clickRequired)
        XCTAssertEqual(ring.click(section: 5), .select(5))
        XCTAssertFalse(ring.isOpen)
    }

    func testClickRequiredClickOnNothingDismisses() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .clickRequired)
        XCTAssertEqual(ring.click(section: nil), .dismiss)
        XCTAssertFalse(ring.isOpen)
    }

    func testClickRequiredSecondHotkeyPressDismisses() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .clickRequired)
        XCTAssertEqual(ring.hotkeyDown(mode: .clickRequired), .dismiss)
        XCTAssertFalse(ring.isOpen)
    }

    // MARK: Shared

    func testEscapeDismissesInBothModes() {
        for mode in OpenMode.allCases {
            var ring = RingInteraction()
            _ = ring.hotkeyDown(mode: mode)
            ring.pointerMoved(section: 1)
            XCTAssertEqual(ring.escape(), .dismiss, "\(mode)")
            XCTAssertFalse(ring.isOpen)
        }
    }

    func testEventsWhileClosedDoNothing() {
        var ring = RingInteraction()
        XCTAssertEqual(ring.hotkeyUp(), .none)
        XCTAssertEqual(ring.click(section: 1), .none)
        XCTAssertEqual(ring.escape(), .none)
        ring.pointerMoved(section: 2)
        XCTAssertNil(ring.highlighted, "pointer moves are ignored while closed")
    }

    func testModeIsLockedAtOpenTime() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .holdRelease)
        XCTAssertEqual(ring.mode, .holdRelease)
        // A repeated key-down in hold-release mode must not reopen or change mode.
        XCTAssertEqual(ring.hotkeyDown(mode: .clickRequired), .none)
        XCTAssertEqual(ring.mode, .holdRelease)
    }

    func testReopenAfterCloseStartsClean() {
        var ring = RingInteraction()
        _ = ring.hotkeyDown(mode: .holdRelease)
        ring.pointerMoved(section: 3)
        _ = ring.hotkeyUp()
        XCTAssertEqual(ring.hotkeyDown(mode: .holdRelease), .opened)
        XCTAssertNil(ring.highlighted)
    }

    // MARK: Placeholder ring + settings sanitising

    func testPlaceholderRingHasRequestedCountAndUniqueIDs() {
        let sections = PlaceholderRing.sections(count: 7)
        XCTAssertEqual(sections.count, 7)
        XCTAssertEqual(Set(sections.map(\.id)).count, 7)
        XCTAssertEqual(sections.first?.title, "1")
    }

    func testSectionCountClamping() {
        XCTAssertEqual(PlaceholderRing.clampedCount(0), PlaceholderRing.minCount)
        XCTAssertEqual(PlaceholderRing.clampedCount(1_000), PlaceholderRing.maxCount)
        XCTAssertEqual(PlaceholderRing.clampedCount(8), 8)
    }
}
