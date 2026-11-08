import XCTest
@testable import RoundelCore

/// Expanding-arc navigation. The state machine receives what is under the pointer (`RingHit`) and the time.
///
/// root:  0:a0   1:g1[ 0:c0  1:g2[ 0:d0  1:g3[ 0:e0  1:e1 ]  2:d2 ]  2:c2 ]   2:a2   3:g4[ f0  f1 ]
/// hits:  root g1 = .item(0,1)   level-1 g2 = .item(1,1)   level-2 g3 = .item(2,1)   level-3 e1 = .item(3,1)
final class RingNavigationTests: XCTestCase {
    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }

    private var ring: [Node] {
        [action("a0"),
         group("g1", [action("c0"), group("g2", [action("d0"), group("g3", [action("e0"), action("e1")]), action("d2")]), action("c2")]),
         action("a2"),
         group("g4", [action("f0"), action("f1")])]
    }

    private func config(_ mode: OpenMode = .holdRelease, expandMs: Int = 120) -> RoundelConfig {
        RoundelConfig(version: 1, settings: ConfigSettings(openMode: mode, expandDelayMs: expandMs), ring: ring)
    }

    private func opened(_ mode: OpenMode = .holdRelease, expandMs: Int = 120, metrics: RingMetrics = .standard) -> RingInteraction {
        var nav = RingInteraction(metrics: metrics)
        XCTAssertEqual(nav.hotkeyDown(config: config(mode, expandMs: expandMs)), .opened)
        return nav
    }

    private func item(_ level: Int, _ index: Int) -> RingHit { .item(level: level, index: index) }

    /// Hover `hit` from `start`; returns the first non-`.none` outcome and the time it happened (or `.none`, last time).
    @discardableResult
    private func hover(_ nav: inout RingInteraction, _ hit: RingHit, from start: Double, for duration: Double) -> (RingOutcome, Double) {
        var time = start
        let end = start + duration
        while time <= end + 1e-9 {
            let outcome = nav.update(hit: hit, now: time)
            if outcome != .none { return (outcome, time) }
            time += 0.01
        }
        return (.none, end)
    }

    /// Opens g1 (and optionally deeper groups) by hovering. Returns the time after the last expansion.
    private func openChain(_ nav: inout RingInteraction, depth: Int, from start: Double = 0) -> Double {
        let hits = [item(0, 1), item(1, 1), item(2, 1)]
        var time = start
        for hit in hits.prefix(depth) {
            let (outcome, at) = hover(&nav, hit, from: time, for: 1)
            XCTAssertEqual(outcome, .layoutChanged)
            time = at + 0.001
        }
        XCTAssertEqual(nav.path.count, depth)
        return time
    }

    // MARK: Opening

    func testOpenStartsAtTheRootWithNothingHovered() {
        let nav = opened()
        XCTAssertTrue(nav.isOpen)
        XCTAssertEqual(nav.path, [])
        XCTAssertEqual(nav.levelCount, 1)
        XCTAssertEqual(nav.nodes(atLevel: 0).map(\.id), ["a0", "g1", "a2", "g4"])
        XCTAssertNil(nav.hovered)
        XCTAssertTrue(nav.highlightedItems.isEmpty)
    }

    // MARK: Hover opens the arc after expandDelay

    func testHoveringAGroupOpensItsArcAfterTheDelay() {
        var nav = opened()
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0), .none)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.1), .none)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.119), .none)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.12), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.levelCount, 2)
        XCTAssertEqual(nav.nodes(atLevel: 1).map(\.id), ["c0", "g2", "c2"])
    }

    func testDelayComesFromTheConfig() {
        var slow = opened(expandMs: 600)
        _ = slow.update(hit: item(0, 1), now: 0)
        XCTAssertEqual(slow.update(hit: item(0, 1), now: 0.5), .none)
        XCTAssertEqual(slow.update(hit: item(0, 1), now: 0.6), .layoutChanged)

        var instant = opened(expandMs: 0)
        XCTAssertEqual(instant.update(hit: item(0, 1), now: 0), .layoutChanged, "zero delay opens on the first sample")
    }

    func testDelayRestartsWhenThePointerMovesToAnotherGroup() {
        var nav = opened()
        _ = nav.update(hit: item(0, 1), now: 0)
        _ = nav.update(hit: item(0, 3), now: 0.1)
        XCTAssertEqual(nav.update(hit: item(0, 3), now: 0.2), .none, "only 0.1 s on g4")
        XCTAssertEqual(nav.update(hit: item(0, 3), now: 0.22), .layoutChanged)
        XCTAssertEqual(nav.path, ["g4"])
    }

    func testLeavesNeverOpenAnything() {
        var nav = opened()
        XCTAssertEqual(hover(&nav, item(0, 0), from: 0, for: 5).0, .none)
        XCTAssertEqual(nav.path, [])
    }

    func testHoveredItemIsTracked() {
        var nav = opened()
        _ = nav.update(hit: item(0, 2), now: 0)
        XCTAssertEqual(nav.hovered, RingItemRef(level: 0, index: 2))
        _ = nav.update(hit: .gap, now: 0.1)
        XCTAssertNil(nav.hovered)
    }

    // MARK: Sticky parent

    func testParentStaysWhileThePointerIsInTheChildBand() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        for hit in [item(1, 0), item(1, 2), item(1, 0), item(1, 2)] {
            XCTAssertEqual(hover(&nav, hit, from: t, for: 3).0, .none)
        }
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testParentStaysHighlightedWhileTheChildIsHovered() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        _ = nav.update(hit: item(1, 0), now: t + 0.5)
        XCTAssertTrue(nav.isHighlighted(level: 0, index: 1), "the parent")
        XCTAssertTrue(nav.isHighlighted(level: 1, index: 0), "the hovered child")
        XCTAssertFalse(nav.isHighlighted(level: 1, index: 2))
        XCTAssertFalse(nav.isHighlighted(level: 0, index: 2))
    }

    func testPointerBackOnTheParentKeepsEverythingOpen() {
        var nav = opened()
        let t = openChain(&nav, depth: 3)
        XCTAssertEqual(hover(&nav, item(0, 1), from: t, for: 5).0, .none)
        XCTAssertEqual(nav.path, ["g1", "g2", "g3"], "still on the open chain")
    }

    // MARK: Switching parents in the root band

    func testHoveringADifferentRootGroupSwitchesAfterTheDelay() {
        var nav = opened()
        let t = openChain(&nav, depth: 2)
        _ = nav.update(hit: item(0, 3), now: t)
        XCTAssertEqual(nav.update(hit: item(0, 3), now: t + 0.119), .none)
        XCTAssertEqual(nav.update(hit: item(0, 3), now: t + 0.12), .layoutChanged)
        XCTAssertEqual(nav.path, ["g4"], "the old chain is gone, only the new group is open")
    }

    func testHoveringARootLeafClosesTheArcAfterTheHysteresis() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        _ = nav.update(hit: item(0, 2), now: t)
        XCTAssertEqual(nav.update(hit: item(0, 2), now: t + 0.149), .none)
        XCTAssertEqual(nav.update(hit: item(0, 2), now: t + 0.15), .layoutChanged)
        XCTAssertEqual(nav.path, [])
    }

    func testHoveringALevelOneLeafClosesOnlyTheDeeperArcs() {
        var nav = opened()
        let t = openChain(&nav, depth: 3)
        _ = nav.update(hit: item(1, 0), now: t)
        XCTAssertEqual(nav.update(hit: item(1, 0), now: t + 0.15), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1"])
    }

    // MARK: Diagonal moves

    func testCrossingANeighbouringRootSectionOnTheWayToTheArcDoesNotCloseIt() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        // Diagonal: leaves g1's section sideways into the neighbouring leaf, crosses the gap, lands far along the arc.
        XCTAssertEqual(nav.update(hit: item(0, 2), now: t + 0.00), .none)
        XCTAssertEqual(nav.update(hit: item(0, 2), now: t + 0.04), .none)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 0.05), .none)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 0.08), .none)
        XCTAssertEqual(nav.update(hit: item(1, 2), now: t + 0.09), .none)
        XCTAssertEqual(hover(&nav, item(1, 2), from: t + 0.1, for: 5).0, .none)
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testCrossingANeighbouringGroupDoesNotSwitchIfThePointerLeavesInTime() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        _ = nav.update(hit: item(0, 3), now: t)
        XCTAssertEqual(nav.update(hit: item(0, 3), now: t + 0.08), .none, "under the 0.12 s delay")
        XCTAssertEqual(nav.update(hit: item(1, 1), now: t + 0.09), .none)
        XCTAssertEqual(hover(&nav, item(1, 1), from: t + 0.1, for: 2).0, .layoutChanged, "g2 opens from the child band; g4 never took over")
        XCTAssertEqual(nav.path, ["g1", "g2"])
    }

    // MARK: Close hysteresis

    func testSlippingIntoAGapAndBackWithinTheHysteresisKeepsTheArc() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 1.0), .none)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 1.14), .none)
        XCTAssertEqual(nav.update(hit: item(1, 0), now: t + 1.145), .none)
        XCTAssertEqual(nav.update(hit: item(1, 0), now: t + 1.3), .none)
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testStayingAwayForTheWholeHysteresisClosesEverythingOpenedByHover() {
        for away in [RingHit.gap, .center, .outside] {
            var nav = opened()
            let t = openChain(&nav, depth: 2)
            XCTAssertEqual(nav.update(hit: away, now: t + 1.0), .none, "\(away)")
            XCTAssertEqual(nav.update(hit: away, now: t + 1.149), .none, "\(away)")
            XCTAssertEqual(nav.update(hit: away, now: t + 1.15), .layoutChanged, "\(away)")
            XCTAssertEqual(nav.path, [], "\(away)")
        }
    }

    func testTheHysteresisIsContinuousNotCumulative() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        _ = nav.update(hit: .gap, now: t + 1.0)
        _ = nav.update(hit: .gap, now: t + 1.1)
        _ = nav.update(hit: item(1, 0), now: t + 1.11)
        _ = nav.update(hit: .gap, now: t + 1.12)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 1.22), .none, "only 0.10 s since the last return")
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testHysteresisValueComesFromTheMetrics() {
        var metrics = RingMetrics.standard
        metrics.closeHysteresis = 0.4
        var nav = opened(metrics: metrics)
        let t = openChain(&nav, depth: 1)
        _ = nav.update(hit: .gap, now: t + 1.0)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 1.39), .none)
        XCTAssertEqual(nav.update(hit: .gap, now: t + 1.4), .layoutChanged)
    }

    // MARK: Depth 3

    func testNestedDepthThreeOpensOneArcPerLevel() {
        var nav = opened()
        _ = openChain(&nav, depth: 3)
        XCTAssertEqual(nav.path, ["g1", "g2", "g3"])
        XCTAssertEqual(nav.levelCount, 4)
        XCTAssertEqual(nav.nodes(atLevel: 3).map(\.id), ["e0", "e1"])
        XCTAssertEqual(nav.highlightedItems, [RingItemRef(level: 0, index: 1), RingItemRef(level: 1, index: 1), RingItemRef(level: 2, index: 1)])
    }

    func testReleaseOnALeafAtDepthThreeRunsIt() {
        var nav = opened()
        let t = openChain(&nav, depth: 3)
        _ = nav.update(hit: item(3, 1), now: t + 0.2)
        XCTAssertEqual(nav.hotkeyUp(), .select("e1"))
        XCTAssertFalse(nav.isOpen)
        XCTAssertEqual(nav.path, [])
    }

    func testReleaseOnAGroupAtAnyDepthCancels() {
        for (hit, depth) in [(item(0, 1), 1), (item(1, 1), 2), (item(2, 1), 3)] {
            var nav = opened()
            let t = openChain(&nav, depth: depth)
            _ = nav.update(hit: hit, now: t + 0.2)
            XCTAssertEqual(nav.hotkeyUp(), .dismiss, "\(hit)")
        }
    }

    // MARK: Release (hold-and-release mode)

    func testReleaseOnARootLeafRunsIt() {
        var nav = opened()
        _ = nav.update(hit: item(0, 2), now: 0)
        XCTAssertEqual(nav.hotkeyUp(), .select("a2"))
    }

    func testReleaseInAGapTheCenterOrOutsideCancels() {
        for hit in [RingHit.gap, .center, .outside] {
            var nav = opened()
            let t = openChain(&nav, depth: 1)
            _ = nav.update(hit: item(1, 0), now: t)
            _ = nav.update(hit: hit, now: t + 0.05)
            XCTAssertEqual(nav.hotkeyUp(), .dismiss, "\(hit)")
        }
    }

    func testReleaseBeforeAnythingWasHoveredCancels() {
        var nav = opened()
        XCTAssertEqual(nav.hotkeyUp(), .dismiss)
    }

    func testHoldModeIgnoresClicks() {
        var nav = opened()
        let t = openChain(&nav, depth: 1)
        XCTAssertEqual(nav.click(item(1, 0)), .none)
        XCTAssertEqual(nav.click(.center), .none)
        XCTAssertEqual(nav.click(.outside), .none)
        XCTAssertTrue(nav.isOpen)
        _ = t
    }

    func testHoldModeRepeatedHotkeyDownChangesNothing() {
        var nav = opened()
        _ = openChain(&nav, depth: 1)
        XCTAssertEqual(nav.hotkeyDown(config: config()), .none)
        XCTAssertEqual(nav.path, ["g1"])
    }

    // MARK: Click mode

    func testClickModeUsesTheSameHoverLogicToOpenArcs() {
        var nav = opened(.clickRequired)
        _ = nav.update(hit: item(0, 1), now: 0)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.12), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.pinnedDepth, 0, "hovering does not pin")
    }

    func testClickModeIgnoresKeyUp() {
        var nav = opened(.clickRequired)
        _ = openChain(&nav, depth: 1)
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertTrue(nav.isOpen)
    }

    func testClickOnALeafRunsItAtAnyDepth() {
        var nav = opened(.clickRequired)
        XCTAssertEqual(nav.click(item(0, 2)), .select("a2"))

        var deep = opened(.clickRequired)
        _ = openChain(&deep, depth: 3)
        XCTAssertEqual(deep.click(item(3, 0)), .select("e0"))
    }

    func testClickOnAClosedGroupOpensAndPinsItImmediately() {
        var nav = opened(.clickRequired)
        XCTAssertEqual(nav.click(item(0, 1)), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.pinnedDepth, 1)
    }

    func testClickOnAnArcOpenedByHoverPinsIt() {
        var nav = opened(.clickRequired)
        _ = openChain(&nav, depth: 1)
        XCTAssertEqual(nav.click(item(0, 1)), .none, "already open: just pinned")
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.pinnedDepth, 1)
    }

    func testClickingAPinnedGroupAgainClosesItsArc() {
        var nav = opened(.clickRequired)
        _ = nav.click(item(0, 1))
        XCTAssertEqual(nav.click(item(0, 1)), .layoutChanged)
        XCTAssertEqual(nav.path, [])
        XCTAssertEqual(nav.pinnedDepth, 0)
    }

    func testAToggledClosedGroupDoesNotReopenWhileThePointerStaysOnIt() {
        var nav = opened(.clickRequired)
        _ = nav.click(item(0, 1))
        _ = nav.click(item(0, 1))   // closed again
        XCTAssertEqual(hover(&nav, item(0, 1), from: 0, for: 3).0, .none, "no immediate re-open under the cursor")
        XCTAssertEqual(nav.path, [])

        _ = nav.update(hit: item(0, 0), now: 3.1)   // leaves ...
        _ = nav.update(hit: item(0, 1), now: 3.2)   // ... and comes back
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 3.32), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testPinnedArcSurvivesThePointerWanderingOff() {
        var nav = opened(.clickRequired)
        _ = nav.click(item(0, 1))
        XCTAssertEqual(hover(&nav, .gap, from: 0, for: 5).0, .none)
        XCTAssertEqual(hover(&nav, .outside, from: 5, for: 5).0, .none)
        XCTAssertEqual(hover(&nav, item(0, 2), from: 10, for: 5).0, .none, "and over a sibling leaf")
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testAnUnpinnedArcStillClosesInClickMode() {
        var nav = opened(.clickRequired)
        let t = openChain(&nav, depth: 1)
        XCTAssertEqual(hover(&nav, .gap, from: t, for: 1).0, .layoutChanged)
        XCTAssertEqual(nav.path, [])
    }

    func testHoveringAnotherGroupReplacesAPinnedOne() {
        var nav = opened(.clickRequired)
        _ = nav.click(item(0, 1))
        _ = nav.update(hit: item(0, 3), now: 0)
        XCTAssertEqual(nav.update(hit: item(0, 3), now: 0.12), .layoutChanged)
        XCTAssertEqual(nav.path, ["g4"])
        XCTAssertEqual(nav.pinnedDepth, 0)
    }

    func testPinningADeeperGroupPinsItsAncestorsToo() {
        var nav = opened(.clickRequired)
        _ = openChain(&nav, depth: 2)
        XCTAssertEqual(nav.click(item(1, 1)), .none)
        XCTAssertEqual(nav.pinnedDepth, 2)
        XCTAssertEqual(hover(&nav, .gap, from: 0, for: 5).0, .none)
        XCTAssertEqual(nav.path, ["g1", "g2"])
    }

    func testClickingAChildGroupOfAPinnedParentOpensAndPinsIt() {
        var nav = opened(.clickRequired)
        _ = nav.click(item(0, 1))
        XCTAssertEqual(nav.click(item(1, 1)), .layoutChanged)
        XCTAssertEqual(nav.path, ["g1", "g2"])
        XCTAssertEqual(nav.pinnedDepth, 2)
        XCTAssertEqual(nav.click(item(1, 1)), .layoutChanged, "toggle the child closed")
        XCTAssertEqual(nav.path, ["g1"])
        XCTAssertEqual(nav.pinnedDepth, 1, "its parent stays pinned")
    }

    func testClickOnTheCenterOrOutsideClosesEverything() {
        for hit in [RingHit.center, .outside] {
            var nav = opened(.clickRequired)
            _ = nav.click(item(0, 1))
            _ = nav.click(item(1, 1))
            XCTAssertEqual(nav.click(hit), .dismiss, "\(hit)")
            XCTAssertFalse(nav.isOpen)
            XCTAssertEqual(nav.path, [])
        }
    }

    func testClickInAGapDoesNothing() {
        var nav = opened(.clickRequired)
        _ = nav.click(item(0, 1))
        XCTAssertEqual(nav.click(.gap), .none)
        XCTAssertTrue(nav.isOpen)
        XCTAssertEqual(nav.path, ["g1"])
    }

    func testSecondHotkeyPressClosesEverythingAtAnyDepth() {
        var nav = opened(.clickRequired)
        _ = openChain(&nav, depth: 3)
        XCTAssertEqual(nav.hotkeyDown(config: config(.clickRequired)), .dismiss)
        XCTAssertFalse(nav.isOpen)
    }

    // MARK: Escape, reset, robustness

    func testEscapeClosesEverythingFromDepthThreeInBothModes() {
        for mode in OpenMode.allCases {
            var nav = opened(mode)
            _ = openChain(&nav, depth: 3)
            XCTAssertEqual(nav.escape(), .dismiss, "\(mode)")
            XCTAssertFalse(nav.isOpen)
            XCTAssertEqual(nav.hotkeyDown(config: config(mode)), .opened)
            XCTAssertEqual(nav.path, [], "reopens at the root")
            XCTAssertEqual(nav.pinnedDepth, 0)
            XCTAssertNil(nav.hovered)
        }
    }

    func testEventsWhileClosedDoNothing() {
        var nav = RingInteraction()
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0), .none)
        XCTAssertEqual(nav.hotkeyUp(), .none)
        XCTAssertEqual(nav.click(item(0, 0)), .none)
        XCTAssertEqual(nav.escape(), .none)
        XCTAssertNil(nav.hovered)
    }

    func testHitsThatPointAtNothingAreTreatedAsAGap() {
        var nav = opened()
        XCTAssertEqual(nav.update(hit: item(0, 99), now: 0), .none)
        XCTAssertNil(nav.hovered)
        XCTAssertEqual(nav.update(hit: item(4, 0), now: 0.1), .none, "a level that is not open")
        XCTAssertNil(nav.hovered)
        XCTAssertEqual(nav.update(hit: item(-1, 0), now: 0.2), .none)
        XCTAssertNil(nav.hovered)
        var click = opened(.clickRequired)
        XCTAssertEqual(click.click(item(0, 99)), .none)
        XCTAssertTrue(click.isOpen)
    }

    func testSettingsAreReadAtOpenTime() {
        var nav = RingInteraction()
        XCTAssertEqual(nav.hotkeyDown(config: config(.holdRelease, expandMs: 100)), .opened)
        XCTAssertEqual(nav.mode, .holdRelease)
        _ = nav.escape()
        XCTAssertEqual(nav.hotkeyDown(config: config(.clickRequired, expandMs: 500)), .opened)
        XCTAssertEqual(nav.mode, .clickRequired)
        _ = nav.update(hit: item(0, 1), now: 0)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.4), .none)
        XCTAssertEqual(nav.update(hit: item(0, 1), now: 0.5), .layoutChanged)
    }

    func testSingleItemRingAndHugeRing() {
        let single = RoundelConfig(ring: [action("only")])
        var nav = RingInteraction()
        _ = nav.hotkeyDown(config: single)
        _ = nav.update(hit: item(0, 0), now: 0)
        XCTAssertEqual(nav.hotkeyUp(), .select("only"))

        let many = RoundelConfig(ring: (0..<200).map { action("n\($0)") })
        _ = nav.hotkeyDown(config: many)
        _ = nav.update(hit: item(0, 150), now: 0)
        XCTAssertEqual(nav.hotkeyUp(), .select("n150"))
    }
}

/// The ring is live from its very first frame: nothing in the logic waits for a visual to finish appearing.
final class RingFirstFrameTests: XCTestCase {
    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }

    func testReleasingTheHotkeyAtTheSameInstantTheRingOpensCommitsTheLeafUnderThePointer() {
        let config = RoundelConfig(version: 1, settings: ConfigSettings(openMode: .holdRelease), ring: [action("a"), action("b"), group("g", [action("c")])])
        var nav = RingInteraction()
        XCTAssertEqual(nav.hotkeyDown(config: config), .opened)
        // The same instant: no time has passed, so no animation could have run.
        XCTAssertEqual(nav.update(hit: .item(level: 0, index: 1), now: 0), .none)
        XCTAssertEqual(nav.hotkeyUp(), .select("b"))
    }

    func testHitTestingAndTheLayoutDoNotDependOnAnyViewState() {
        // RingLayout.make and hit(dx:dy:) take nothing but nodes, metrics and the pointer; there is no animation input.
        let nodes: [Node] = (0..<6).map { action("n\($0)") }
        let layout = RingLayout.make(root: nodes, path: [])
        let first = (0..<360).map { layout.hit(dx: 80 * sin(Double($0) * .pi / 180), dy: 80 * cos(Double($0) * .pi / 180)) }
        let second = (0..<360).map { layout.hit(dx: 80 * sin(Double($0) * .pi / 180), dy: 80 * cos(Double($0) * .pi / 180)) }
        XCTAssertEqual(first, second)
        XCTAssertEqual(layout.hit(dx: 0, dy: 80), .item(level: 0, index: 0))
    }
}
