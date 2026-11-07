import XCTest
@testable import RoundelCore

/// Navigation through nested groups. Time is injected (seconds), the state machine has no timers.
final class RingNavigationTests: XCTestCase {
    // root:  0:a0  1:g1[ 0:c0  1:g2[ 0:d0  1:d1 ]  2:c2 ]  2:a2
    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }

    private var ring: [Node] {
        [action("a0"),
         group("g1", [action("c0"), group("g2", [action("d0"), action("d1")]), action("c2")]),
         action("a2")]
    }

    private func config(_ mode: OpenMode, dwellMs: Int = 250, centerDwellMs: Int = 250) -> RoundelConfig {
        RoundelConfig(version: 1,
                      settings: ConfigSettings(openMode: mode, dwellMs: dwellMs, centerDwellMs: centerDwellMs),
                      ring: ring)
    }

    /// Open a ring and hover-dwell into `g1` (root section 1). Returns the time at which the level changed.
    private func openInsideG1(_ nav: inout RingInteraction, mode: OpenMode = .holdRelease) -> Double {
        XCTAssertEqual(nav.hotkeyDown(config: config(mode)), .opened)
        if mode == .clickRequired {
            XCTAssertEqual(nav.click(.section(1)), .levelChanged)
            return 0
        }
        XCTAssertEqual(nav.update(section: 1, now: 0), .none)
        XCTAssertEqual(nav.update(section: 1, now: 0.25), .levelChanged)
        return 0.25
    }

    // MARK: Opening

    func testOpenStartsAtRoot() {
        var nav = RingInteraction()
        XCTAssertEqual(nav.hotkeyDown(config: config(.holdRelease)), .opened)
        XCTAssertTrue(nav.isOpen)
        XCTAssertEqual(nav.path, [])
        XCTAssertEqual(nav.depth, 0)
        XCTAssertEqual(nav.currentNodes.map(\.id), ["a0", "g1", "a2"])
        XCTAssertNil(nav.highlighted)
        XCTAssertEqual(nav.mode, .holdRelease)
    }

    func testModeComesFromConfigAtOpenTime() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.clickRequired))
        XCTAssertEqual(nav.mode, .clickRequired)
    }

    // MARK: Hover mode: select / cancel

    func testReleaseOnActionSelectsItsId() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        _ = nav.update(section: 2, now: 0.1)
        XCTAssertEqual(nav.highlighted, 2)
        XCTAssertEqual(nav.hotkeyUp(), .select("a2"))
        XCTAssertFalse(nav.isOpen)
        XCTAssertNil(nav.highlighted)
    }

    func testReleaseInCenterDismisses() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        _ = nav.update(section: 0, now: 0)
        _ = nav.update(section: nil, now: 0.05)
        XCTAssertEqual(nav.hotkeyUp(), .dismiss)
    }

    func testReleaseOnGroupCancels() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        _ = nav.update(section: 1, now: 0)
        XCTAssertEqual(nav.hotkeyUp(), .dismiss, "dwell not finished and it is a group: cancel, never select")
        XCTAssertFalse(nav.isOpen)
    }

    func testReleaseOnActionInsideNestedLevelSelects() {
        var nav = RingInteraction()
        let t = openInsideG1(&nav)
        _ = nav.update(section: 2, now: t + 0.1)
        XCTAssertEqual(nav.hotkeyUp(), .select("c2"))
    }

    func testReleaseInCenterAtDepthDismissesEverything() {
        var nav = RingInteraction()
        let t = openInsideG1(&nav)
        _ = nav.update(section: nil, now: t + 0.05)
        XCTAssertEqual(nav.hotkeyUp(), .dismiss)
        XCTAssertEqual(nav.path, [], "state is reset for the next open")
    }

    // MARK: Hover mode: dwell into a group

    func testDwellOnGroupEntersAfterConfiguredTime() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        XCTAssertEqual(nav.update(section: 1, now: 0), .none)
        XCTAssertEqual(nav.update(section: 1, now: 0.2), .none)
        XCTAssertEqual(nav.update(section: 1, now: 0.25), .levelChanged)
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.depth, 1)
        XCTAssertEqual(nav.currentNodes.map(\.id), ["c0", "g2", "c2"])
        XCTAssertNil(nav.highlighted)
    }

    func testDwellUsesConfiguredDuration() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease, dwellMs: 600))
        _ = nav.update(section: 1, now: 0)
        XCTAssertEqual(nav.update(section: 1, now: 0.5), .none)
        XCTAssertEqual(nav.update(section: 1, now: 0.6), .levelChanged)
    }

    func testDwellRestartsWhenSectionChanges() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        _ = nav.update(section: 1, now: 0)
        _ = nav.update(section: 0, now: 0.2)
        _ = nav.update(section: 1, now: 0.3)
        XCTAssertEqual(nav.update(section: 1, now: 0.5), .none, "only 0.2 s since coming back")
        XCTAssertEqual(nav.update(section: 1, now: 0.55), .levelChanged)
    }

    func testNoDwellOnActions() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        for step in 0..<40 {
            XCTAssertEqual(nav.update(section: 0, now: Double(step) * 0.1), .none)
        }
        XCTAssertEqual(nav.depth, 0)
    }

    func testDwellProgress() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        XCTAssertNil(nav.dwellProgress(at: 0))
        _ = nav.update(section: 1, now: 1.0)
        XCTAssertEqual(nav.dwellProgress(at: 1.125) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(nav.dwellProgress(at: 9) ?? -1, 1, accuracy: 1e-9, "capped at 1")
        _ = nav.update(section: 0, now: 1.2)
        XCTAssertNil(nav.dwellProgress(at: 1.2), "no progress on an action")
    }

    // MARK: No cascade after swapping rings

    func testNoImmediateCascadeIntoGroupUnderTheCursor() {
        var nav = RingInteraction()
        let t = openInsideG1(&nav)
        // Cursor is still where it was, and in the child ring that spot is g2 (section 1).
        XCTAssertEqual(nav.update(section: 1, now: t + 0.01), .none)
        XCTAssertEqual(nav.update(section: 1, now: t + 2.0), .none, "must leave and come back first")
        XCTAssertEqual(nav.depth, 1)

        _ = nav.update(section: 0, now: t + 2.1)
        _ = nav.update(section: 1, now: t + 2.2)
        XCTAssertEqual(nav.update(section: 1, now: t + 2.45), .levelChanged)
        XCTAssertEqual(nav.path, ["g1", "g2"])
    }

    // MARK: Going back with the center

    func testCenterDwellGoesBackOneLevel() {
        var nav = RingInteraction()
        let t = openInsideG1(&nav)
        _ = nav.update(section: 0, now: t + 0.01)   // first sample after the swap
        XCTAssertEqual(nav.update(section: nil, now: t + 1.0), .none)
        XCTAssertEqual(nav.update(section: nil, now: t + 1.2), .none)
        XCTAssertEqual(nav.update(section: nil, now: t + 1.25), .levelChanged)
        XCTAssertEqual(nav.path, [])
        XCTAssertEqual(nav.currentNodes.map(\.id), ["a0", "g1", "a2"])
    }

    func testCenterDwellUsesItsOwnDuration() {
        var nav = RingInteraction()
        XCTAssertEqual(nav.hotkeyDown(config: config(.holdRelease, dwellMs: 250, centerDwellMs: 700)), .opened)
        _ = nav.update(section: 1, now: 0)
        XCTAssertEqual(nav.update(section: 1, now: 0.25), .levelChanged)
        _ = nav.update(section: 0, now: 0.3)
        _ = nav.update(section: nil, now: 1.0)
        XCTAssertEqual(nav.update(section: nil, now: 1.6), .none)
        XCTAssertEqual(nav.update(section: nil, now: 1.7), .levelChanged)
    }

    func testQuickCrossingThroughCenterDoesNotGoBack() {
        var nav = RingInteraction()
        let t = openInsideG1(&nav)
        _ = nav.update(section: 0, now: t + 0.01)
        _ = nav.update(section: nil, now: t + 1.0)
        XCTAssertEqual(nav.update(section: nil, now: t + 1.1), .none)
        XCTAssertEqual(nav.update(section: 2, now: t + 1.15), .none)
        XCTAssertEqual(nav.update(section: nil, now: t + 1.2), .none)
        XCTAssertEqual(nav.update(section: nil, now: t + 1.4), .none, "dwell restarted at 1.2")
        XCTAssertEqual(nav.depth, 1)
    }

    func testCenterDwellDoesNotCascadeBackAgain() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        // root -> g1 -> g2
        _ = nav.update(section: 1, now: 0); XCTAssertEqual(nav.update(section: 1, now: 0.25), .levelChanged)
        _ = nav.update(section: 0, now: 0.3); _ = nav.update(section: 1, now: 0.4)
        XCTAssertEqual(nav.update(section: 1, now: 0.65), .levelChanged)
        XCTAssertEqual(nav.depth, 2)
        // back once
        _ = nav.update(section: 0, now: 0.7)
        _ = nav.update(section: nil, now: 1.0)
        XCTAssertEqual(nav.update(section: nil, now: 1.25), .levelChanged)
        XCTAssertEqual(nav.depth, 1)
        // still parked in the center: must NOT pop again until the pointer leaves and returns
        XCTAssertEqual(nav.update(section: nil, now: 3.0), .none)
        XCTAssertEqual(nav.depth, 1)
        _ = nav.update(section: 0, now: 3.1)
        _ = nav.update(section: nil, now: 3.2)
        XCTAssertEqual(nav.update(section: nil, now: 3.45), .levelChanged)
        XCTAssertEqual(nav.depth, 0)
    }

    func testCenterDwellAtRootDoesNothing() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        for step in 0..<20 {
            XCTAssertEqual(nav.update(section: nil, now: Double(step) * 0.2), .none)
        }
        XCTAssertTrue(nav.isOpen)
    }

    // MARK: Hover mode ignores clicks and repeated hotkey presses

    func testHoldModeIgnoresClicks() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        _ = nav.update(section: 2, now: 0)
        XCTAssertEqual(nav.click(.section(2)), .none)
        XCTAssertEqual(nav.click(.center), .none)
        XCTAssertEqual(nav.click(.outside), .none)
        XCTAssertTrue(nav.isOpen)
    }

    func testHoldModeRepeatedHotkeyDownKeepsState() {
        var nav = RingInteraction()
        let t = openInsideG1(&nav)
        XCTAssertEqual(nav.hotkeyDown(config: config(.holdRelease)), .none)
        XCTAssertEqual(nav.path, ["g1"])
        _ = t
    }

    // MARK: Click mode

    func testClickModeNeverDwells() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.clickRequired))
        for step in 0..<40 {
            XCTAssertEqual(nav.update(section: 1, now: Double(step) * 0.1), .none)
        }
        XCTAssertEqual(nav.highlighted, 1, "hover still highlights")
        XCTAssertEqual(nav.depth, 0)
        XCTAssertNil(nav.dwellProgress(at: 4))
    }

    func testClickOnGroupEntersImmediately() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.clickRequired))
        XCTAssertEqual(nav.click(.section(1)), .levelChanged)
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.currentNodes.map(\.id), ["c0", "g2", "c2"])
        XCTAssertTrue(nav.isOpen)
    }

    func testClickOnActionSelects() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.clickRequired))
        XCTAssertEqual(nav.click(.section(2)), .select("a2"))
        XCTAssertFalse(nav.isOpen)
    }

    func testClickCenterGoesBackThenDismissesAtRoot() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.clickRequired))
        XCTAssertEqual(nav.click(.section(1)), .levelChanged)
        XCTAssertEqual(nav.click(.section(1)), .levelChanged)   // g2
        XCTAssertEqual(nav.path, ["g1", "g2"])
        XCTAssertEqual(nav.click(.center), .levelChanged)
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.click(.center), .levelChanged)
        XCTAssertEqual(nav.path, [])
        XCTAssertEqual(nav.click(.center), .dismiss)
        XCTAssertFalse(nav.isOpen)
    }

    func testClickOutsideDismissesFromAnyDepth() {
        var nav = RingInteraction()
        _ = openInsideG1(&nav, mode: .clickRequired)
        XCTAssertEqual(nav.click(.outside), .dismiss)
        XCTAssertFalse(nav.isOpen)
    }

    func testClickModeIgnoresKeyUp() {
        var nav = RingInteraction()
        _ = openInsideG1(&nav, mode: .clickRequired)
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertTrue(nav.isOpen)
        XCTAssertEqual(nav.depth, 1)
    }

    func testClickModeSecondHotkeyPressDismissesAtDepth() {
        var nav = RingInteraction()
        _ = openInsideG1(&nav, mode: .clickRequired)
        XCTAssertEqual(nav.hotkeyDown(config: config(.clickRequired)), .dismiss)
        XCTAssertFalse(nav.isOpen)
    }

    // MARK: Escape / reset / robustness

    func testEscapeDismissesFromDepthAndResetsPath() {
        for mode in OpenMode.allCases {
            var nav = RingInteraction()
            _ = openInsideG1(&nav, mode: mode)
            XCTAssertEqual(nav.escape(), .dismiss, "\(mode)")
            XCTAssertFalse(nav.isOpen)
            XCTAssertEqual(nav.hotkeyDown(config: config(mode)), .opened)
            XCTAssertEqual(nav.path, [], "reopens at the root")
            XCTAssertEqual(nav.currentNodes.map(\.id), ["a0", "g1", "a2"])
        }
    }

    func testEventsWhileClosedDoNothing() {
        var nav = RingInteraction()
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertEqual(nav.click(.section(0)), .none)
        XCTAssertEqual(nav.click(.outside), .none)
        XCTAssertEqual(nav.escape(), .none)
        XCTAssertEqual(nav.update(section: 1, now: 0), .none)
        XCTAssertNil(nav.highlighted)
    }

    func testOutOfRangeSectionIsIgnored() {
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: config(.holdRelease))
        XCTAssertEqual(nav.update(section: 99, now: 0), .none)
        XCTAssertEqual(nav.update(section: -1, now: 0), .none)
        XCTAssertNil(nav.highlighted)
        XCTAssertEqual(nav.click(.section(99)), .none, "hold mode ignores clicks anyway")
        var click = RingInteraction()
        _ = click.hotkeyDown(config: config(.clickRequired))
        XCTAssertEqual(click.click(.section(99)), .none)
        XCTAssertTrue(click.isOpen)
    }

    func testSingleSectionLevel() {
        let single = RoundelConfig(version: 1, settings: ConfigSettings(), ring: [action("only")])
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: single)
        _ = nav.update(section: 0, now: 0)
        XCTAssertEqual(nav.hotkeyUp(), .select("only"))
    }

    func testManySectionsLevel() {
        let many = RoundelConfig(version: 1, settings: ConfigSettings(),
                                 ring: (0..<200).map { action("n\($0)") })
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: many)
        _ = nav.update(section: 150, now: 0)
        XCTAssertEqual(nav.hotkeyUp(), .select("n150"))
    }
}
