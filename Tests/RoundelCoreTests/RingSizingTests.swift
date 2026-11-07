import XCTest
@testable import RoundelCore

/// Sizes of rings and arcs. Every tunable value lives in `RingMetrics`, so tests can change one and see the effect.
final class RingSizingTests: XCTestCase {
    private let metrics = RingMetrics.standard

    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func actions(_ prefix: String, _ count: Int) -> [Node] { (0..<count).map { action("\(prefix)\($0)") } }

    // MARK: Named, tunable values

    func testTheStandardValues() {
        XCTAssertEqual(metrics.deadZoneRadius, 30)
        XCTAssertEqual(metrics.rootMinOuterRadius, 124)
        XCTAssertEqual(metrics.rootMaxOuterRadius, 220)
        XCTAssertEqual(metrics.bandGap, 8)
        XCTAssertEqual(metrics.bandThickness, 64)
        XCTAssertEqual(metrics.minArcPerItem, 44)
        XCTAssertEqual(metrics.maxItemAngle, 55 * .pi / 180, accuracy: 1e-12)
        XCTAssertEqual(metrics.maxArcSweep, 300 * .pi / 180, accuracy: 1e-12)
        XCTAssertEqual(metrics.arcRadiusCap, 360)
        XCTAssertEqual(metrics.closeHysteresis, 0.15)
    }

    func testChangingAValueChangesTheResult() {
        var thick = metrics
        thick.bandThickness = 80
        XCTAssertEqual(thick.arcBand(level: 1, itemCount: 3, innerRadius: 132).outerRadius, 212)
        var spaced = metrics
        spaced.bandGap = 20
        let layout = RingLayout.make(root: [.group(GroupNode(id: "g", title: "g", children: actions("c", 2))), action("b")], path: ["g"], metrics: spaced)
        XCTAssertEqual(layout.bands[1].innerRadius, layout.bands[0].outerRadius + 20, accuracy: 1e-9)
    }

    // MARK: Root ring

    func testSmallRootRingsUseTheMinimumSize() {
        for count in 1...12 { XCTAssertEqual(metrics.rootBand(itemCount: count).outerRadius, metrics.rootMinOuterRadius, "N=\(count)") }
    }

    func testRootRingGrowsMonotonicallyThenStopsAtTheCap() {
        var previous = 0.0
        for count in 1...60 {
            let radius = metrics.rootBand(itemCount: count).outerRadius
            XCTAssertGreaterThanOrEqual(radius, previous, "N=\(count)")
            XCTAssertLessThanOrEqual(radius, metrics.rootMaxOuterRadius)
            previous = radius
        }
        XCTAssertGreaterThan(metrics.rootBand(itemCount: 20).outerRadius, metrics.rootMinOuterRadius)
        XCTAssertEqual(metrics.rootBand(itemCount: 100).outerRadius, metrics.rootMaxOuterRadius)
        XCTAssertEqual(metrics.rootBand(itemCount: 100, maxOuterRadius: 150).outerRadius, 150, "a smaller (screen) cap wins")
        XCTAssertEqual(metrics.rootBand(itemCount: 100, maxOuterRadius: 50).outerRadius, metrics.rootMinOuterRadius, "never below the minimum")
    }

    func testRootCrowding() {
        XCTAssertFalse(metrics.rootBand(itemCount: 12).isCrowded)
        XCTAssertFalse(metrics.rootBand(itemCount: 20).isCrowded)
        XCTAssertTrue(metrics.rootBand(itemCount: 25).isCrowded)
        XCTAssertTrue(metrics.rootBand(itemCount: 200).isCrowded)
    }

    func testRootItemZeroIsCenteredAtTwelveOClockAndTheRingIsAFullCircle() {
        for count in [1, 4, 7] {
            let band = metrics.rootBand(itemCount: count)
            XCTAssertEqual(band.centerAngle(ofItem: 0), 0, accuracy: 1e-12)
            XCTAssertEqual(band.sweep, 2 * .pi, accuracy: 1e-9)
            XCTAssertEqual(band.level, 0)
            XCTAssertEqual(band.innerRadius, metrics.deadZoneRadius)
        }
    }

    func testPanelSideIsAnEvenWholeNumberThatContainsTheOutermostBand() {
        for outer in [124.0, 130.4, 196.0, 340.7, 412.0] {
            let side = metrics.panelSide(forOuterRadius: outer)
            XCTAssertEqual(side.truncatingRemainder(dividingBy: 2), 0, "outer \(outer)")
            XCTAssertGreaterThanOrEqual(side, 2 * (outer + metrics.panelPadding))
        }
    }

    func testIconSizesStayReadable() {
        XCTAssertEqual(metrics.rootBand(itemCount: 6).iconSize, 24)
        for count in [1, 6, 30, 500] {
            let size = metrics.rootBand(itemCount: count).iconSize
            XCTAssertGreaterThanOrEqual(size, 12)
            XCTAssertLessThanOrEqual(size, 24)
        }
        XCTAssertLessThan(metrics.rootBand(itemCount: 500).iconSize, 24)
    }

    // MARK: Arcs

    func testSmallArcKeepsItsPositionAndUsesTheStandardThickness() {
        let band = metrics.arcBand(level: 1, itemCount: 3, innerRadius: 132)
        XCTAssertEqual(band.innerRadius, 132)
        XCTAssertEqual(band.outerRadius, 132 + metrics.bandThickness)
        let mid = 132 + metrics.bandThickness / 2
        XCTAssertEqual(band.itemWidth, metrics.minArcPerItem / mid, accuracy: 1e-9)
        XCTAssertEqual(band.sweep, 3 * band.itemWidth, accuracy: 1e-9)
        XCTAssertFalse(band.isCrowded)
        XCTAssertEqual(band.level, 1)
        XCTAssertEqual(band.count, 3)
    }

    func testAnItemNeverGetsWiderThanTheMaximumAngle() {
        let band = metrics.arcBand(level: 1, itemCount: 1, innerRadius: 10)
        XCTAssertEqual(band.itemWidth, metrics.maxItemAngle, accuracy: 1e-12)
    }

    func testManyChildrenPushTheArcOutwardBeforeAnythingTightens() {
        let few = metrics.arcBand(level: 1, itemCount: 5, innerRadius: 132)
        let many = metrics.arcBand(level: 1, itemCount: 30, innerRadius: 132)
        XCTAssertGreaterThan(many.innerRadius, few.innerRadius)
        XCTAssertEqual(many.outerRadius - many.innerRadius, metrics.bandThickness, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(many.outerRadius, metrics.arcRadiusCap)
        XCTAssertLessThanOrEqual(many.sweep, metrics.maxArcSweep + 1e-9)
        XCTAssertFalse(many.isCrowded, "growing was enough")
        let mid = (many.innerRadius + many.outerRadius) / 2
        XCTAssertGreaterThanOrEqual(many.itemWidth * mid, metrics.minArcPerItem - 1e-6, "every item still has its minimum arc length")
    }

    func testAtTheCapItemsTightenAndTheArcIsCrowded() {
        let band = metrics.arcBand(level: 1, itemCount: 60, innerRadius: 132)
        XCTAssertEqual(band.outerRadius, metrics.arcRadiusCap, accuracy: 1e-9)
        XCTAssertEqual(band.sweep, metrics.maxArcSweep, accuracy: 1e-9)
        XCTAssertEqual(band.itemWidth, metrics.maxArcSweep / 60, accuracy: 1e-12)
        XCTAssertTrue(band.isCrowded)
    }

    func testTheSweepNeverExceedsTheMaximumForAnyCount() {
        for count in 1...300 {
            let band = metrics.arcBand(level: 1, itemCount: count, innerRadius: 132)
            XCTAssertLessThanOrEqual(band.sweep, metrics.maxArcSweep + 1e-9, "N=\(count)")
            XCTAssertLessThanOrEqual(band.outerRadius, metrics.arcRadiusCap + 1e-9, "N=\(count)")
            XCTAssertGreaterThanOrEqual(band.iconSize, 12)
            XCTAssertLessThanOrEqual(band.iconSize, 24)
        }
    }

    func testAnArcAlreadyBeyondTheCapIsStillPlacedJustWithoutGrowth() {
        let band = metrics.arcBand(level: 5, itemCount: 4, innerRadius: 400)
        XCTAssertEqual(band.innerRadius, 400)
        XCTAssertEqual(band.outerRadius, 400 + metrics.bandThickness)
        XCTAssertTrue(band.exceedsRadiusCap)
        XCTAssertFalse(metrics.arcBand(level: 1, itemCount: 4, innerRadius: 132).exceedsRadiusCap)
    }

    func testScreenLimitedCapIsHonouredForArcs() {
        let band = metrics.arcBand(level: 1, itemCount: 60, innerRadius: 132, maxOuterRadius: 250)
        XCTAssertEqual(band.outerRadius, 250, accuracy: 1e-9)
        XCTAssertTrue(band.isCrowded)
    }

    // MARK: Warnings across a whole config

    func testNoWarningsForTheDefaultConfig() {
        XCTAssertTrue(metrics.levelWarnings(in: DefaultConfig.config).isEmpty)
    }

    func testCrowdedRootAndCrowdedGroupAreListedWithTheirPaths() {
        let config = RoundelConfig(ring: [
            .group(GroupNode(id: "small", title: "s", children: actions("s", 5))),
            .group(GroupNode(id: "big", title: "b", children: actions("b", 60) + [
                .group(GroupNode(id: "inner", title: "i", children: actions("i", 70))),
            ])),
        ] + actions("r", 30))

        let warnings = metrics.levelWarnings(in: config)
        XCTAssertEqual(warnings.filter { $0.kind == .crowded }.map(\.path), [[], ["big"], ["big", "inner"]])
        XCTAssertEqual(warnings.filter { $0.kind == .crowded }.map(\.count), [32, 61, 70])
    }

    func testTooDeepNestingIsFlaggedFromTheLevelThatDoesNotFit() {
        func nest(_ ids: [String]) -> [Node] {
            guard let first = ids.first else { return actions("leaf", 2) }
            return [.group(GroupNode(id: first, title: first, children: nest(Array(ids.dropFirst())))), action("sibling-\(first)")]
        }
        let config = RoundelConfig(ring: nest(["g1", "g2", "g3", "g4", "g5"]))
        let deep = metrics.levelWarnings(in: config).filter { $0.kind == .tooDeep }
        XCTAssertEqual(deep.map(\.path.count), [4, 5], "three arcs fit; the fourth and fifth do not")
        XCTAssertTrue(metrics.levelWarnings(in: RoundelConfig(ring: nest(["g1", "g2", "g3"]))).filter { $0.kind == .tooDeep }.isEmpty)
    }
}
