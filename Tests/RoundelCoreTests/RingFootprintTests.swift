import XCTest
@testable import RoundelCore

/// The footprint is the area of the screen the ring owns: it receives mouse events (swallows clicks) even where
/// nothing is drawn. Root = the whole disc, dead zone included. Each open arc = the annular sector from the first
/// item's start angle to the last item's end angle, radially from the previous band's outer edge to its own.
final class RingFootprintTests: XCTestCase {
    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }
    private func actions(_ count: Int, prefix: String = "c") -> [Node] { (0..<count).map { action("\(prefix)\($0)") } }

    /// y-up offset for a clockwise-from-12 angle in degrees.
    private func inside(_ layout: RingLayout, _ degrees: Double, _ radius: Double) -> Bool {
        let radians = degrees * .pi / 180
        return layout.footprintContains(dx: radius * sin(radians), dy: radius * cos(radians))
    }

    private func hit(_ layout: RingLayout, _ degrees: Double, _ radius: Double) -> RingHit {
        let radians = degrees * .pi / 180
        return layout.hit(dx: radius * sin(radians), dy: radius * cos(radians))
    }

    private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Six root sections; "g" (index 0, at 12 o'clock) opens a 5-item arc.
    private var oneArc: RingLayout {
        RingLayout.make(root: [group("g", actions(5))] + actions(5, prefix: "r"), path: ["g"])
    }

    // MARK: Root

    func testRootDiscIncludingDeadZoneAndCenterIsInside() {
        let layout = RingLayout.make(root: actions(6), path: [])
        XCTAssertTrue(layout.footprintContains(dx: 0, dy: 0))
        XCTAssertTrue(inside(layout, 90, layout.deadZoneRadius - 1), "dead zone")
        XCTAssertTrue(inside(layout, 200, layout.bands[0].outerRadius - 1), "ring body")
    }

    func testRootOuterEdgeIsInsideAndJustBeyondIsOutside() {
        let layout = RingLayout.make(root: actions(6), path: [])
        let outer = layout.bands[0].outerRadius
        XCTAssertTrue(layout.footprintContains(dx: 0, dy: outer), "exactly on the edge")
        XCTAssertTrue(inside(layout, 45, outer - 0.01))
        XCTAssertFalse(inside(layout, 45, outer + 1))
    }

    func testGapBetweenRootSectionsAndTheHoleBetweenDeadZoneAndBandAreInside() {
        let layout = RingLayout.make(root: actions(6), path: [])
        let band = layout.bands[0]
        // Exactly on the boundary between two sections, and in any radial hole below the band.
        XCTAssertTrue(inside(layout, 30, (band.innerRadius + band.outerRadius) / 2))
        let hole = (layout.deadZoneRadius + band.innerRadius) / 2
        XCTAssertTrue(inside(layout, 120, hole))
    }

    // MARK: One arc

    func testRadialGapBetweenRootAndArcIsInsideAtTheArcAngleButStaysAHitGap() {
        let layout = oneArc
        let root = layout.bands[0], arc = layout.bands[1]
        let radius = (root.outerRadius + arc.innerRadius) / 2
        XCTAssertGreaterThan(arc.innerRadius, root.outerRadius, "precondition: there is a radial gap")
        XCTAssertTrue(inside(layout, 0, radius))
        XCTAssertEqual(hit(layout, 0, radius), .gap, "navigation still sees a gap")
    }

    func testFootprintOfAnArcStartsAtTheParentsOuterEdge() {
        let layout = oneArc
        let root = layout.bands[0]
        XCTAssertTrue(inside(layout, 0, root.outerRadius + 0.5))
    }

    func testArcBodyIsInsideAndBeyondItsOuterEdgeIsOutside() {
        let layout = oneArc
        let arc = layout.bands[1]
        XCTAssertTrue(inside(layout, 0, (arc.innerRadius + arc.outerRadius) / 2))
        XCTAssertTrue(inside(layout, 0, arc.outerRadius))
        XCTAssertFalse(inside(layout, 0, arc.outerRadius + 1))
    }

    func testRadialGapIsClickThroughBesideTheArc() {
        let layout = oneArc
        let root = layout.bands[0], arc = layout.bands[1]
        let radius = (root.outerRadius + arc.innerRadius) / 2
        // 180° is the far side: no arc there, and beyond the root disc.
        XCTAssertFalse(inside(layout, 180, radius))
    }

    func testBetweenArcItemsIsInside() {
        let layout = oneArc
        let arc = layout.bands[1]
        let boundary = degrees(arc.startAngle + 2 * arc.itemWidth)   // seam between item 1 and item 2
        XCTAssertTrue(inside(layout, boundary, (arc.innerRadius + arc.outerRadius) / 2))
    }

    // MARK: Arc ends

    func testArcEndsAreInclusiveAndTheSpaceBeyondThemIsOutside() {
        let layout = oneArc
        let arc = layout.bands[1]
        let radius = (arc.innerRadius + arc.outerRadius) / 2
        let start = degrees(arc.startAngle)
        let end = degrees(arc.startAngle + arc.sweep)

        XCTAssertTrue(inside(layout, start + 0.5, radius), "just inside the start")
        XCTAssertTrue(inside(layout, end - 0.5, radius), "just inside the end")
        XCTAssertFalse(inside(layout, start - 0.5, radius), "just before the start")
        XCTAssertFalse(inside(layout, end + 0.5, radius), "just after the end")
    }

    func testRadialGapNextToTheArcEndsIsAlsoClickThrough() {
        let layout = oneArc
        let root = layout.bands[0], arc = layout.bands[1]
        let radius = (root.outerRadius + arc.innerRadius) / 2
        XCTAssertTrue(inside(layout, degrees(arc.startAngle) + 0.5, radius))
        XCTAssertFalse(inside(layout, degrees(arc.startAngle) - 0.5, radius))
        XCTAssertFalse(inside(layout, degrees(arc.startAngle + arc.sweep) + 0.5, radius))
    }

    func testArcEndsWorkWhenTheArcWrapsPastTwelveOClock() {
        // Arc centered at 12 o'clock has a negative start angle: -sweep/2.
        let layout = oneArc
        let arc = layout.bands[1]
        XCTAssertLessThan(arc.startAngle, 0, "precondition: the arc straddles 12 o'clock")
        let radius = (arc.innerRadius + arc.outerRadius) / 2
        XCTAssertTrue(inside(layout, -0.5, radius))
        XCTAssertTrue(inside(layout, 0.5, radius))
        XCTAssertFalse(inside(layout, 180, radius))
    }

    func testASingleSectionRootIsInsideAllAround() {
        let layout = RingLayout.make(root: actions(1), path: [])
        for angle in stride(from: 0.0, to: 360, by: 20) { XCTAssertTrue(inside(layout, angle, layout.bands[0].outerRadius - 1), "\(angle)°") }
    }

    // MARK: Several levels

    func testTwoOpenArcsEachContributeTheirOwnSector() {
        // g (root index 0) -> arc 1 with "h" at index 2 (a group) -> arc 2.
        let layout = RingLayout.make(
            root: [group("g", [action("a"), action("b"), group("h", actions(4, prefix: "d")), action("e")])] + actions(5, prefix: "r"),
            path: ["g", "h"]
        )
        XCTAssertEqual(layout.bands.count, 3)
        let arc1 = layout.bands[1], arc2 = layout.bands[2]

        // The bridging gap between arc 1 and arc 2, at arc 2's angle, is inside.
        let hAngle = degrees(arc1.centerAngle(ofItem: 2))
        let bridge = (arc1.outerRadius + arc2.innerRadius) / 2
        XCTAssertGreaterThan(arc2.innerRadius, arc1.outerRadius, "precondition: there is a gap between the arcs")
        XCTAssertTrue(inside(layout, hAngle, bridge))
        XCTAssertEqual(hit(layout, hAngle, bridge), .gap)

        // Same radius, but off arc 2's sector (still within arc 1's extent): click-through.
        let offAngle = degrees(arc2.startAngle) - 3
        XCTAssertFalse(inside(layout, offAngle, bridge))

        // Arc 2's body is inside, beyond its outer edge is outside.
        XCTAssertTrue(inside(layout, hAngle, (arc2.innerRadius + arc2.outerRadius) / 2))
        XCTAssertFalse(inside(layout, hAngle, arc2.outerRadius + 1))
    }

    func testClosingAnArcRemovesItsSectorFromTheFootprint() {
        let open = oneArc
        let closed = RingLayout.make(root: [group("g", actions(5))] + actions(5, prefix: "r"), path: [])
        let arc = open.bands[1]
        let probe = (arc.innerRadius + arc.outerRadius) / 2
        XCTAssertTrue(inside(open, 0, probe))
        XCTAssertFalse(inside(closed, 0, probe))
    }

    func testAnArcWithManyChildrenStillStartsAtThePreviousBandsOuterEdge() {
        let layout = RingLayout.make(root: [group("g", actions(40))] + actions(5, prefix: "r"), path: ["g"])
        let root = layout.bands[0], arc = layout.bands[1]
        XCTAssertGreaterThan(arc.innerRadius, root.outerRadius + RingMetrics.standard.bandGap + 1, "precondition: the arc was pushed outwards")
        XCTAssertTrue(inside(layout, 0, root.outerRadius + 1))
        XCTAssertTrue(inside(layout, 0, (root.outerRadius + arc.innerRadius) / 2))
    }

    // MARK: Consistency with hit-testing

    func testEverythingNavigationCanHitIsInsideTheFootprint() {
        let layout = RingLayout.make(
            root: [group("g", [action("a"), group("h", actions(4)), action("e")])] + actions(5, prefix: "r"),
            path: ["g", "h"]
        )
        let limit = Int(layout.outerRadius) + 20
        for x in stride(from: -limit, through: limit, by: 3) {
            for y in stride(from: -limit, through: limit, by: 3) {
                let result = layout.hit(dx: Double(x), dy: Double(y))
                switch result {
                case .center, .item: XCTAssertTrue(layout.footprintContains(dx: Double(x), dy: Double(y)), "\(result) at (\(x), \(y))")
                case .outside: XCTAssertFalse(layout.footprintContains(dx: Double(x), dy: Double(y)), "outside at (\(x), \(y))")
                case .gap: break   // either, depending on where the gap is
                }
            }
        }
    }

    func testInvalidInputIsNotInside() {
        let layout = oneArc
        XCTAssertFalse(layout.footprintContains(dx: .nan, dy: 0))
        XCTAssertFalse(layout.footprintContains(dx: 0, dy: .infinity))
    }

    func testFootprintHasOneRegionPerBand() {
        XCTAssertEqual(oneArc.footprint.count, 2)
        XCTAssertEqual(RingLayout.make(root: actions(3), path: []).footprint.count, 1)
    }
}
