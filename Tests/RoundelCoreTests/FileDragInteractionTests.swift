import XCTest
@testable import RoundelCore

/// Dragging files onto the ring: the drop is the commit. Releasing the hotkey does neither commit nor cancel.
///
/// root:  0:a0   1:g1[ 0:c0  1:g2[ 0:d0  1:d1 ] ]   2:a2
final class FileDragInteractionTests: XCTestCase {
    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }

    private var ring: [Node] {
        [action("a0"), group("g1", [action("c0"), group("g2", [action("d0"), action("d1")])]), action("a2")]
    }

    private func opened(_ mode: OpenMode = .holdRelease, dragging: Bool = true) -> RingInteraction {
        var nav = RingInteraction()
        let config = RoundelConfig(version: 1, settings: ConfigSettings(openMode: mode, expandDelayMs: 120), ring: ring)
        XCTAssertEqual(nav.hotkeyDown(config: config, dragging: dragging), .opened)
        return nav
    }

    private func item(_ level: Int, _ index: Int) -> RingHit { .item(level: level, index: index) }

    /// Hovers `hit` long enough for an arc to open; returns the time afterwards.
    @discardableResult
    private func hover(_ nav: inout RingInteraction, _ hit: RingHit, from start: Double = 0, for duration: Double = 0.3) -> Double {
        var time = start
        while time <= start + duration { _ = nav.update(hit: hit, now: time); time += 0.01 }
        return time
    }

    // MARK: Hotkey during a drag

    func testTheRingRemembersItOpenedDuringADrag() {
        XCTAssertTrue(opened().isDragging)
        XCTAssertFalse(opened(dragging: false).isDragging)
    }

    func testReleasingTheHotkeyOnALeafDuringADragDoesNotCommit() {
        var nav = opened()
        hover(&nav, item(0, 0))
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertTrue(nav.isOpen)
    }

    func testReleasingTheHotkeyOverNothingDuringADragDoesNotCancel() {
        var nav = opened()
        hover(&nav, .gap)
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertTrue(nav.isOpen)
    }

    func testWithoutADragReleaseStillCommitsAsBefore() {
        var nav = opened(dragging: false)
        hover(&nav, item(0, 0))
        XCTAssertEqual(nav.hotkeyUp(), .select("a0"))
    }

    // MARK: Hover still works during a drag

    func testHoveringAGroupOpensItsArcAfterTheExpandDelayDuringADrag() {
        var nav = opened()
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0), .none)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.12), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testNestedArcsOpenOneLevelAtATimeDuringADrag() {
        var nav = opened()
        var time = hover(&nav, item(0, 1))
        time = hover(&nav, item(1, 1), from: time)
        XCTAssertEqual(nav.path, ["g1", "g2"])
        XCTAssertEqual(nav.levelCount, 3)
    }

    // MARK: The drop

    func testDroppingOnARootLeafRunsItAndClosesTheRing() {
        var nav = opened()
        XCTAssertEqual(nav.drop(on: item(0, 0)), .select("a0"))
        XCTAssertFalse(nav.isOpen)
        XCTAssertFalse(nav.isDragging)
    }

    func testDroppingOnALeafInANestedArcRunsIt() {
        var nav = opened()
        var time = hover(&nav, item(0, 1))
        time = hover(&nav, item(1, 1), from: time)
        XCTAssertEqual(nav.drop(on: item(2, 1)), .select("d1"))
    }

    func testDroppingOnAGroupGapCenterOrOutsideDoesNothingAndClosesTheRing() {
        for hit: RingHit in [item(0, 1), .gap, .center, .outside] {
            var nav = opened()
            XCTAssertEqual(nav.drop(on: hit), .dismiss, "\(hit)")
            XCTAssertFalse(nav.isOpen, "\(hit)")
        }
    }

    func testADropOnAnItemThatIsNotThereIsRefused() {
        var nav = opened()
        XCTAssertEqual(nav.drop(on: item(5, 0)), .dismiss)
        var again = opened()
        XCTAssertEqual(again.drop(on: item(0, 9)), .dismiss)
    }

    func testCanDropOnlyOnLeaves() {
        var nav = opened()
        hover(&nav, item(0, 0))
        XCTAssertTrue(nav.canDrop(on: item(0, 0)))
        XCTAssertTrue(nav.canDrop(on: item(0, 2)))
        XCTAssertFalse(nav.canDrop(on: item(0, 1)), "a group")
        XCTAssertFalse(nav.canDrop(on: .gap))
        XCTAssertFalse(nav.canDrop(on: .center))
        XCTAssertFalse(nav.canDrop(on: .outside))
        XCTAssertFalse(nav.canDrop(on: item(3, 0)), "no such level")
    }

    func testDropIsIgnoredWhenNoDragIsInProgress() {
        var nav = opened(dragging: false)
        XCTAssertEqual(nav.drop(on: item(0, 0)), .none)
        XCTAssertTrue(nav.isOpen)
        XCTAssertFalse(nav.canDrop(on: item(0, 0)))
    }

    func testDropWorksInClickMode() {
        var nav = opened(.clickRequired)
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertEqual(nav.drop(on: item(0, 2)), .select("a2"))
    }

    // MARK: The drag ends elsewhere

    func testTheDragEndingWithoutADropClosesTheRing() {
        var nav = opened()
        hover(&nav, item(0, 0))
        XCTAssertEqual(nav.dragEnded(), .dismiss)
        XCTAssertFalse(nav.isOpen)
    }

    func testDragEndedMeansNothingWithoutADrag() {
        var nav = opened(dragging: false)
        XCTAssertEqual(nav.dragEnded(), .none)
        XCTAssertTrue(nav.isOpen)
    }

    func testEscapeStillClosesDuringADrag() {
        var nav = opened()
        XCTAssertEqual(nav.escape(), .dismiss)
        XCTAssertFalse(nav.isDragging)
    }

    func testTheNextOpeningStartsWithoutTheOldDragState() {
        var nav = opened()
        _ = nav.drop(on: item(0, 0))
        let config = RoundelConfig(version: 1, settings: ConfigSettings(), ring: ring)
        XCTAssertEqual(nav.hotkeyDown(config: config), .opened)
        XCTAssertFalse(nav.isDragging)
    }
}
