import XCTest
@testable import RoundelCore

/// Offsets are y-up (AppKit screen space): +dy is up on screen, +dx is right.
/// Section 0 is centered at 12 o'clock; indices increase clockwise.
final class RingGeometryTests: XCTestCase {
    private func geometry(_ count: Int, dead: Double = 20, outer: Double? = nil) -> RingGeometry {
        RingGeometry(sectionCount: count, deadZoneRadius: dead, outerRadius: outer)
    }

    // MARK: Cardinal directions

    func testFourSectionsCardinalDirections() {
        let g = geometry(4)
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: 100), 0, "up")
        XCTAssertEqual(g.sectionIndex(dx: 100, dy: 0), 1, "right")
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: -100), 2, "down")
        XCTAssertEqual(g.sectionIndex(dx: -100, dy: 0), 3, "left")
    }

    func testYAxisIsNotFlipped() {
        // Regression: SwiftUI is y-down, AppKit is y-up. Geometry is y-up.
        let g = geometry(2)
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: 50), 0)
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: -50), 1)
    }

    func testSixSectionsClockwiseOrder() {
        let g = geometry(6) // centers at 0°, 60°, 120°, ...
        let centers: [(Double, Int)] = [(0, 0), (60, 1), (120, 2), (180, 3), (240, 4), (300, 5)]
        for (degrees, expected) in centers {
            let (dx, dy) = offset(degrees: degrees, radius: 100)
            XCTAssertEqual(g.sectionIndex(dx: dx, dy: dy), expected, "\(degrees)°")
        }
    }

    // MARK: Boundaries and wraparound

    func testBoundaryBetweenSectionsFourSections() {
        let g = geometry(4) // boundaries at 45°, 135°, 225°, 315°
        XCTAssertEqual(g.sectionIndex(dx: offset(degrees: 44, radius: 100).0, dy: offset(degrees: 44, radius: 100).1), 0)
        XCTAssertEqual(g.sectionIndex(dx: offset(degrees: 46, radius: 100).0, dy: offset(degrees: 46, radius: 100).1), 1)
    }

    func testWraparoundAroundTwelveOClock() {
        let g = geometry(8) // section 0 spans -22.5°...22.5°
        for degrees in [-22.0, -1.0, 0.0, 1.0, 22.0] {
            let (dx, dy) = offset(degrees: degrees, radius: 100)
            XCTAssertEqual(g.sectionIndex(dx: dx, dy: dy), 0, "\(degrees)°")
        }
        let (dx, dy) = offset(degrees: -23, radius: 100)
        XCTAssertEqual(g.sectionIndex(dx: dx, dy: dy), 7, "just counter-clockwise of section 0 is the last section")
    }

    func testSingleSectionAlwaysZeroOutsideDeadZone() {
        let g = geometry(1)
        for degrees in stride(from: 0.0, to: 360.0, by: 15.0) {
            let (dx, dy) = offset(degrees: degrees, radius: 100)
            XCTAssertEqual(g.sectionIndex(dx: dx, dy: dy), 0, "\(degrees)°")
        }
    }

    func testEverySectionReachableAtItsCenterForManyCounts() {
        for count in 1...24 {
            let g = geometry(count)
            for index in 0..<count {
                let degrees = 360.0 / Double(count) * Double(index)
                let (dx, dy) = offset(degrees: degrees, radius: 100)
                XCTAssertEqual(g.sectionIndex(dx: dx, dy: dy), index, "N=\(count) section \(index)")
            }
        }
    }

    func testIndexAlwaysInRangeAcrossFullCircle() {
        for count in [2, 3, 5, 7, 12, 24] {
            let g = geometry(count)
            for tenth in 0..<3600 {
                let (dx, dy) = offset(degrees: Double(tenth) / 10, radius: 100)
                let index = g.sectionIndex(dx: dx, dy: dy)
                XCTAssertNotNil(index)
                XCTAssertTrue((0..<count).contains(index ?? -1), "N=\(count) at \(Double(tenth) / 10)°")
            }
        }
    }

    // MARK: Dead zone

    func testInsideDeadZoneIsNil() {
        let g = geometry(6, dead: 20)
        XCTAssertNil(g.sectionIndex(dx: 0, dy: 0))
        XCTAssertNil(g.sectionIndex(dx: 0, dy: 19.9))
        XCTAssertNil(g.sectionIndex(dx: -14, dy: -14)) // r ≈ 19.8
    }

    func testDeadZoneEdgeIsOutside() {
        let g = geometry(4, dead: 20)
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: 20), 0, "exactly on the radius belongs to a section")
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: 20.1), 0)
    }

    func testZeroDeadZoneStillNilAtExactCenter() {
        let g = geometry(4, dead: 0)
        XCTAssertNil(g.sectionIndex(dx: 0, dy: 0), "angle is undefined at the exact center")
        XCTAssertEqual(g.sectionIndex(dx: 0.001, dy: 0), 1)
    }

    // MARK: Outer radius

    func testOuterRadiusDoesNotAffectHoverIndex() {
        // Hover keeps selecting by angle beyond the ring (flick gesture).
        let g = geometry(4, outer: 120)
        XCTAssertEqual(g.sectionIndex(dx: 0, dy: 500), 0)
    }

    func testIsWithinRing() {
        let g = geometry(4, dead: 20, outer: 120)
        XCTAssertFalse(g.isWithinRing(dx: 0, dy: 10), "dead zone")
        XCTAssertTrue(g.isWithinRing(dx: 0, dy: 60))
        XCTAssertTrue(g.isWithinRing(dx: 0, dy: 120), "outer edge inclusive")
        XCTAssertFalse(g.isWithinRing(dx: 0, dy: 121))
        XCTAssertFalse(g.isWithinRing(dx: 100, dy: 100), "square panel corner is outside the circle")
    }

    func testIsWithinRingWithoutOuterRadiusIsUnbounded() {
        let g = geometry(4, dead: 20, outer: nil)
        XCTAssertTrue(g.isWithinRing(dx: 0, dy: 10_000))
    }

    // MARK: Invalid input

    func testNonPositiveSectionCountReturnsNil() {
        XCTAssertNil(geometry(0).sectionIndex(dx: 0, dy: 100))
        XCTAssertNil(geometry(-3).sectionIndex(dx: 0, dy: 100))
    }

    func testNonFiniteOffsetReturnsNil() {
        let g = geometry(4)
        XCTAssertNil(g.sectionIndex(dx: .nan, dy: 10))
        XCTAssertNil(g.sectionIndex(dx: .infinity, dy: 10))
    }

    // MARK: Section angles (used by the view)

    func testCenterAngles() {
        let g = geometry(4)
        XCTAssertEqual(g.centerAngle(ofSection: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(g.centerAngle(ofSection: 1), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(g.centerAngle(ofSection: 3), 3 * .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(g.sectionWidth, .pi / 2, accuracy: 1e-9)
    }

    // MARK: Helpers

    /// y-up offset for a clockwise-from-12-o'clock angle.
    private func offset(degrees: Double, radius: Double) -> (Double, Double) {
        let radians = degrees * .pi / 180
        return (radius * sin(radians), radius * cos(radians))
    }
}
