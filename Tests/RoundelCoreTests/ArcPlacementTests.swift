import XCTest
@testable import RoundelCore

final class ArcPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let margin = 12.0

    private func deg(_ radians: Double) -> Double { radians * 180 / .pi }
    private func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Arc described the way a band would be: 5 items of 20° = 100° sweep, band 132...196.
    private func place(desired: Double, center: CGPoint, bounds: CGRect? = nil, sweep: Double = 100, itemWidth: Double = 20) -> Double {
        ArcPlacement.centerAngle(
            desired: rad(desired), sweep: rad(sweep), itemWidth: rad(itemWidth),
            innerRadius: 132, outerRadius: 196, ringCenter: center, bounds: bounds ?? screen, margin: margin
        )
    }

    /// Independent check: every sampled point of the arc lies inside the screen minus the margin.
    private func overflow(center angle: Double, at ring: CGPoint, sweep: Double = 100) -> Double {
        let safe = screen.insetBy(dx: margin, dy: margin)
        var total = 0.0
        for radius in [132.0, 196.0] {
            for step in 0...20 {
                let phi = angle - rad(sweep) / 2 + rad(sweep) * Double(step) / 20
                let point = CGPoint(x: ring.x + radius * sin(phi), y: ring.y + radius * cos(phi))
                total += max(0, safe.minX - point.x) + max(0, point.x - safe.maxX) + max(0, safe.minY - point.y) + max(0, point.y - safe.maxY)
            }
        }
        return total
    }

    func testNoShiftWhenTheArcFitsAsIs() {
        XCTAssertEqual(deg(place(desired: 90, center: CGPoint(x: 960, y: 540))), 90, accuracy: 1e-9)
    }

    func testShiftsClockwiseAwayFromTheTopEdge() {
        let ring = CGPoint(x: 960, y: 1000)   // 80 pt below the top edge, parent at 3 o'clock
        let result = place(desired: 90, center: ring)
        XCTAssertEqual(deg(result) - 90, 30, accuracy: 1.0, "smallest shift that clears the edge")
        XCTAssertEqual(overflow(center: result, at: ring), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(overflow(center: rad(90), at: ring), 0, "and it really did not fit unshifted")
    }

    func testShiftsCounterClockwiseAwayFromTheBottomEdge() {
        let ring = CGPoint(x: 960, y: 80)
        let result = place(desired: 90, center: ring)
        XCTAssertEqual(deg(result) - 90, -30, accuracy: 1.0)
        XCTAssertEqual(overflow(center: result, at: ring), 0, accuracy: 1e-9)
    }

    func testShiftsTowardTwelveWhenCloseToTheRightEdge() {
        let ring = CGPoint(x: 1850, y: 540)   // parent at 1:30; the arc would stick out to the right
        let result = place(desired: 45, center: ring)
        XCTAssertLessThan(result, rad(45), "counter-clockwise, toward the top")
        XCTAssertLessThan(overflow(center: result, at: ring), overflow(center: rad(45), at: ring))
    }

    func testShiftsToTheLeftEdgeAsWell() {
        let ring = CGPoint(x: 70, y: 540)   // parent at 10:30 (315°)
        let result = place(desired: 315, center: ring)
        XCTAssertGreaterThan(result, rad(315), "clockwise, toward the top")
        XCTAssertLessThan(overflow(center: result, at: ring), overflow(center: rad(315), at: ring))
    }

    func testShiftNeverDetachesTheParent() {
        // Even in an impossible spot the parent angle must stay inside the arc (max shift = sweep/2 - itemWidth/2 = 40°).
        for ring in [CGPoint(x: 5, y: 5), CGPoint(x: 1915, y: 1075), CGPoint(x: 960, y: 1075), CGPoint(x: 5, y: 540)] {
            for desired in stride(from: 0.0, to: 360, by: 30) {
                let shift = abs(deg(place(desired: desired, center: ring)) - desired)
                XCTAssertLessThanOrEqual(shift, 40.0 + 1e-6, "ring \(ring) desired \(desired)")
            }
        }
    }

    func testImpossibleSpotPicksTheLeastBadPlacement() {
        let ring = CGPoint(x: 1915, y: 1075)   // the top-right corner
        let result = place(desired: 45, center: ring)
        let best = stride(from: 5.0, through: 85, by: 0.5).map { overflow(center: rad($0), at: ring) }.min() ?? 0
        XCTAssertLessThanOrEqual(overflow(center: result, at: ring), best + 1e-6)
    }

    func testChoosesTheSmallestShiftThatFits() {
        // Brute force over the allowed range: no zero-overflow placement is closer to the desired angle than the result.
        let ring = CGPoint(x: 960, y: 1000)
        let result = place(desired: 90, center: ring)
        let fitting = stride(from: 50.0, through: 130, by: 0.5).filter { overflow(center: rad($0), at: ring) == 0 }
        let closest = fitting.map { abs($0 - 90) }.min() ?? .infinity
        XCTAssertEqual(abs(deg(result) - 90), closest, accuracy: 0.51)
    }

    func testIsDeterministic() {
        let ring = CGPoint(x: 960, y: 1000)
        XCTAssertEqual(place(desired: 90, center: ring), place(desired: 90, center: ring))
    }

    func testWorksWithAnglesOutsideZeroToTwoPi() {
        let ring = CGPoint(x: 960, y: 540)
        XCTAssertEqual(ArcPlacement.centerAngle(desired: -0.5, sweep: rad(100), itemWidth: rad(20), innerRadius: 132, outerRadius: 196,
                                                ringCenter: ring, bounds: screen, margin: margin), -0.5, accuracy: 1e-9)
        XCTAssertEqual(ArcPlacement.centerAngle(desired: 7.0, sweep: rad(100), itemWidth: rad(20), innerRadius: 132, outerRadius: 196,
                                                ringCenter: ring, bounds: screen, margin: margin), 7.0, accuracy: 1e-9)
    }

    func testFullCircleArcsAreNeverShifted() {
        let ring = CGPoint(x: 5, y: 5)
        XCTAssertEqual(ArcPlacement.centerAngle(desired: 1, sweep: 2 * .pi, itemWidth: 0.1, innerRadius: 132, outerRadius: 196,
                                                ringCenter: ring, bounds: screen, margin: margin), 1, accuracy: 1e-9)
    }
}
