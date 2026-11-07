import XCTest
@testable import RoundelCore

/// Polar hit-testing: radius picks the band, angle picks the item. Offsets are y-up (AppKit screen space):
/// +dx right, +dy up. Angles are clockwise from 12 o'clock; item 0 of the root ring is centered at 12 o'clock.
final class RingBandTests: XCTestCase {
    private let metrics = RingMetrics.standard

    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }

    private func rootLayout(_ count: Int) -> RingLayout {
        RingLayout.make(root: (0..<count).map { action("n\($0)") }, path: [])
    }

    /// y-up offset for a clockwise-from-12 angle in degrees.
    private func offset(_ degrees: Double, _ radius: Double) -> (dx: Double, dy: Double) {
        let radians = degrees * .pi / 180
        return (radius * sin(radians), radius * cos(radians))
    }

    private func hit(_ layout: RingLayout, _ degrees: Double, _ radius: Double) -> RingHit {
        let o = offset(degrees, radius)
        return layout.hit(dx: o.dx, dy: o.dy)
    }

    // MARK: Root ring (the old RingGeometry cases)

    func testFourSectionsCardinalDirections() {
        let layout = rootLayout(4)
        XCTAssertEqual(layout.hit(dx: 0, dy: 80), .item(level: 0, index: 0), "up")
        XCTAssertEqual(layout.hit(dx: 80, dy: 0), .item(level: 0, index: 1), "right")
        XCTAssertEqual(layout.hit(dx: 0, dy: -80), .item(level: 0, index: 2), "down")
        XCTAssertEqual(layout.hit(dx: -80, dy: 0), .item(level: 0, index: 3), "left")
    }

    func testYAxisIsNotFlipped() {
        let layout = rootLayout(2)
        XCTAssertEqual(layout.hit(dx: 0, dy: 50), .item(level: 0, index: 0))
        XCTAssertEqual(layout.hit(dx: 0, dy: -50), .item(level: 0, index: 1))
    }

    func testClockwiseOrderForSixSections() {
        let layout = rootLayout(6)
        for (degrees, index) in [(0.0, 0), (60, 1), (120, 2), (180, 3), (240, 4), (300, 5)] {
            XCTAssertEqual(hit(layout, degrees, 80), .item(level: 0, index: index), "\(degrees)°")
        }
    }

    func testBoundaryBetweenSections() {
        let layout = rootLayout(4)   // boundaries at 45°, 135°, 225°, 315°
        XCTAssertEqual(hit(layout, 44, 80), .item(level: 0, index: 0))
        XCTAssertEqual(hit(layout, 46, 80), .item(level: 0, index: 1))
    }

    func testWraparoundAtTwelveOClock() {
        let layout = rootLayout(8)
        for degrees in [-22.0, -1, 0, 1, 22] { XCTAssertEqual(hit(layout, degrees, 80), .item(level: 0, index: 0), "\(degrees)°") }
        XCTAssertEqual(hit(layout, -23, 80), .item(level: 0, index: 7))
    }

    func testEveryItemIsReachableAtItsCenterForManyCounts() {
        for count in 1...24 {
            let layout = rootLayout(count)
            let band = layout.bands[0]
            for index in 0..<count {
                let degrees = band.centerAngle(ofItem: index) * 180 / .pi
                let radius = (band.innerRadius + band.outerRadius) / 2
                XCTAssertEqual(hit(layout, degrees, radius), .item(level: 0, index: index), "N=\(count) item \(index)")
            }
        }
    }

    func testSingleSectionCoversTheWholeBand() {
        let layout = rootLayout(1)
        for degrees in stride(from: 0.0, to: 360, by: 15) { XCTAssertEqual(hit(layout, degrees, 80), .item(level: 0, index: 0)) }
    }

    // MARK: Radius picks the band

    func testDeadZoneAndExactCenter() {
        let layout = rootLayout(6)
        XCTAssertEqual(layout.hit(dx: 0, dy: 0), .center)
        XCTAssertEqual(layout.hit(dx: 0, dy: metrics.deadZoneRadius - 0.1), .center)
        XCTAssertEqual(layout.hit(dx: 0, dy: metrics.deadZoneRadius), .item(level: 0, index: 0), "the dead-zone edge is part of the ring")
    }

    func testBeyondTheOuterEdgeIsOutsideNotAFlick() {
        let layout = rootLayout(6)
        let outer = layout.bands[0].outerRadius
        XCTAssertEqual(layout.hit(dx: 0, dy: outer), .item(level: 0, index: 0), "outer edge inclusive")
        XCTAssertEqual(layout.hit(dx: 0, dy: outer + 1), .outside)
        XCTAssertEqual(layout.hit(dx: 5_000, dy: 5_000), .outside)
    }

    func testInvalidInputIsOutside() {
        let layout = rootLayout(4)
        XCTAssertEqual(layout.hit(dx: .nan, dy: 10), .outside)
        XCTAssertEqual(layout.hit(dx: .infinity, dy: 10), .outside)
    }

    // MARK: Child arcs

    // root: 0:a  1:g[ c0 c1 c2 c3 c4 ]  2:b  3:d      (g sits at 90°, 3 o'clock)
    private var oneArc: RingLayout {
        RingLayout.make(root: [action("a"), group("g", (0..<5).map { action("c\($0)") }), action("b"), action("d")], path: ["g"])
    }

    func testArcIsAnotherBandOutsideTheRootSeparatedByAGap() {
        let layout = oneArc
        XCTAssertEqual(layout.bands.count, 2)
        let root = layout.bands[0], arc = layout.bands[1]
        XCTAssertEqual(arc.innerRadius, root.outerRadius + metrics.bandGap, accuracy: 1e-9)
        XCTAssertEqual(arc.outerRadius - arc.innerRadius, metrics.bandThickness, accuracy: 1e-9)
        XCTAssertEqual(arc.level, 1)
        XCTAssertEqual(layout.outerRadius, arc.outerRadius)
    }

    func testArcIsCenteredOnTheParentSection() {
        let layout = oneArc
        let parentAngle = layout.bands[0].centerAngle(ofItem: 1)
        XCTAssertEqual(parentAngle, .pi / 2, accuracy: 1e-9)
        let arc = layout.bands[1]
        XCTAssertEqual(arc.startAngle + arc.sweep / 2, parentAngle, accuracy: 1e-9)
        XCTAssertEqual(arc.centerAngle(ofItem: 2), parentAngle, accuracy: 1e-9, "odd count: the middle child faces the parent")
    }

    func testChildrenRunClockwiseFromTheStartOfTheArc() {
        let layout = oneArc
        let arc = layout.bands[1]
        let radius = (arc.innerRadius + arc.outerRadius) / 2
        for index in 0..<5 {
            let degrees = arc.centerAngle(ofItem: index) * 180 / .pi
            XCTAssertEqual(hit(layout, degrees, radius), .item(level: 1, index: index), "child \(index)")
        }
        XCTAssertLessThan(arc.centerAngle(ofItem: 0), arc.centerAngle(ofItem: 4))
    }

    func testSameAngleDifferentRadiusPicksADifferentBand() {
        let layout = oneArc
        let root = layout.bands[0], arc = layout.bands[1]
        XCTAssertEqual(hit(layout, 90, (root.innerRadius + root.outerRadius) / 2), .item(level: 0, index: 1))
        XCTAssertEqual(hit(layout, 90, (arc.innerRadius + arc.outerRadius) / 2), .item(level: 1, index: 2))
    }

    func testGapBetweenBandsIsAGap() {
        let layout = oneArc
        let root = layout.bands[0], arc = layout.bands[1]
        XCTAssertEqual(hit(layout, 90, (root.outerRadius + arc.innerRadius) / 2), .gap)
        XCTAssertEqual(hit(layout, 200, (root.outerRadius + arc.innerRadius) / 2), .gap, "the gap runs all the way around")
    }

    func testOutsideTheAngularExtentOfAnArcIsAGapNotOutside() {
        let layout = oneArc
        let arc = layout.bands[1]
        let radius = (arc.innerRadius + arc.outerRadius) / 2
        XCTAssertEqual(hit(layout, 270, radius), .gap, "opposite side of the ring: inside the band radius but no item there")
        let justBefore = (arc.startAngle - 0.01) * 180 / .pi
        let justAfter = (arc.startAngle + arc.sweep + 0.01) * 180 / .pi
        XCTAssertEqual(hit(layout, justBefore, radius), .gap)
        XCTAssertEqual(hit(layout, justAfter, radius), .gap)
        XCTAssertEqual(hit(layout, 90, arc.outerRadius + 1), .outside)
    }

    func testRootStaysHittableWhileAnArcIsOpen() {
        let layout = oneArc
        let root = layout.bands[0]
        let radius = (root.innerRadius + root.outerRadius) / 2
        XCTAssertEqual(hit(layout, 0, radius), .item(level: 0, index: 0))
        XCTAssertEqual(hit(layout, 180, radius), .item(level: 0, index: 2))
        XCTAssertEqual(hit(layout, 270, radius), .item(level: 0, index: 3))
    }

    func testSingleChildArc() {
        let layout = RingLayout.make(root: [group("g", [action("only")]), action("b")], path: ["g"])
        let arc = layout.bands[1]
        XCTAssertEqual(arc.count, 1)
        XCTAssertEqual(hit(layout, arc.centerAngle(ofItem: 0) * 180 / .pi, (arc.innerRadius + arc.outerRadius) / 2), .item(level: 1, index: 0))
    }

    // MARK: Nesting

    // g1 > g2 > g3 > leaves
    private var deepRoot: [Node] {
        [action("a"), group("g1", [action("c0"), group("g2", [action("d0"), group("g3", (0..<4).map { action("e\($0)") }), action("d2")]), action("c2")])]
    }

    func testDepthThreeHasFourBandsOutwardWithGaps() {
        let layout = RingLayout.make(root: deepRoot, path: ["g1", "g2", "g3"])
        XCTAssertEqual(layout.bands.count, 4)
        for level in 1..<4 {
            XCTAssertEqual(layout.bands[level].level, level)
            XCTAssertEqual(layout.bands[level].innerRadius, layout.bands[level - 1].outerRadius + metrics.bandGap, accuracy: 1e-9)
        }
    }

    func testEachArcFacesItsOwnParentAtDepthThree() {
        let layout = RingLayout.make(root: deepRoot, path: ["g1", "g2", "g3"])
        let parents = [(level: 0, item: 1), (level: 1, item: 1), (level: 2, item: 1)]
        for (level, item) in parents {
            let parentAngle = layout.bands[level].centerAngle(ofItem: item)
            let arc = layout.bands[level + 1]
            XCTAssertEqual(arc.startAngle + arc.sweep / 2, parentAngle, accuracy: 1e-9, "arc \(level + 1) is centered on its parent")
        }
    }

    func testEveryBandIsHittableAtDepthThree() {
        let layout = RingLayout.make(root: deepRoot, path: ["g1", "g2", "g3"])
        for band in layout.bands {
            let radius = (band.innerRadius + band.outerRadius) / 2
            for item in 0..<band.count {
                let degrees = band.centerAngle(ofItem: item) * 180 / .pi
                XCTAssertEqual(hit(layout, degrees, radius), .item(level: band.level, index: item))
            }
        }
    }

    func testPathStopsAtTheFirstUnknownOrNonGroupId() {
        XCTAssertEqual(RingLayout.make(root: deepRoot, path: ["g1", "nope", "g3"]).bands.count, 2)
        XCTAssertEqual(RingLayout.make(root: deepRoot, path: ["a"]).bands.count, 1, "a leaf has no arc")
        XCTAssertEqual(RingLayout.make(root: deepRoot, path: []).bands.count, 1)
    }

    // MARK: Many children

    func testArcWithManyChildrenGrowsOutwardAndStaysHittable() {
        let many = group("g", (0..<30).map { action("c\($0)") })
        let layout = RingLayout.make(root: [many, action("b")], path: ["g"])
        let arc = layout.bands[1]
        XCTAssertGreaterThan(arc.innerRadius, layout.bands[0].outerRadius + metrics.bandGap, "pushed outward to make room")
        XCTAssertLessThanOrEqual(arc.sweep, metrics.maxArcSweep + 1e-9)
        for item in [0, 7, 15, 29] {
            XCTAssertEqual(hit(layout, arc.centerAngle(ofItem: item) * 180 / .pi, (arc.innerRadius + arc.outerRadius) / 2),
                           .item(level: 1, index: item))
        }
    }

    // MARK: Placement near screen edges (through the layout builder)

    func testLayoutShiftsTheArcAwayFromANearbyScreenEdgeButKeepsTheParentAttached() {
        let ring = [action("a"), group("g", (0..<5).map { action("c\($0)") }), action("b"), action("d")]   // g at 90°
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let placement = ArcPlacement.Context(ringCenter: CGPoint(x: 960, y: 1000), bounds: screen)   // 80 pt below the top edge

        let plain = RingLayout.make(root: ring, path: ["g"])
        let shifted = RingLayout.make(root: ring, path: ["g"], placement: placement)

        let parentAngle = shifted.bands[0].centerAngle(ofItem: 1)
        let arc = shifted.bands[1]
        XCTAssertGreaterThan(arc.startAngle, plain.bands[1].startAngle, "moved clockwise, away from the top edge")
        XCTAssertGreaterThanOrEqual(parentAngle, arc.startAngle, "parent still inside the arc")
        XCTAssertLessThanOrEqual(parentAngle, arc.startAngle + arc.sweep)
        XCTAssertEqual(arc.sweep, plain.bands[1].sweep, accuracy: 1e-9, "only the position changes")
    }

    func testNoShiftWhenThereIsRoom() {
        let ring = [action("a"), group("g", [action("c0"), action("c1")]), action("b")]
        let placement = ArcPlacement.Context(ringCenter: CGPoint(x: 960, y: 540), bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(RingLayout.make(root: ring, path: ["g"], placement: placement).bands[1].startAngle,
                       RingLayout.make(root: ring, path: ["g"]).bands[1].startAngle, accuracy: 1e-12)
    }
}
