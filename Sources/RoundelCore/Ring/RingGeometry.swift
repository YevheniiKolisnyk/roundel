import Foundation

/// Pure ring geometry. All offsets are **y-up** (AppKit screen space), measured from the ring center:
/// `+dx` is right, `+dy` is up. Section 0 is centered at 12 o'clock and indices increase clockwise.
public struct RingGeometry: Equatable, Sendable {
    public var sectionCount: Int
    /// Offsets closer to the center than this select nothing.
    public var deadZoneRadius: Double
    /// Visual radius of the ring. Only used by `isWithinRing`; hover selection ignores it so a flick past the edge still selects.
    public var outerRadius: Double?

    public init(sectionCount: Int, deadZoneRadius: Double, outerRadius: Double? = nil) {
        self.sectionCount = sectionCount
        self.deadZoneRadius = deadZoneRadius
        self.outerRadius = outerRadius
    }

    /// Angular width of one section, in radians.
    public var sectionWidth: Double {
        sectionCount > 0 ? 2 * .pi / Double(sectionCount) : 0
    }

    /// Angle of a section's center, in radians clockwise from 12 o'clock.
    public func centerAngle(ofSection index: Int) -> Double {
        sectionWidth * Double(index)
    }

    /// Section under the given offset, or `nil` in the dead zone, at the exact center, or for invalid input.
    public func sectionIndex(dx: Double, dy: Double) -> Int? {
        guard sectionCount > 0, dx.isFinite, dy.isFinite else { return nil }
        let distance = hypot(dx, dy)
        guard distance > 0, distance >= deadZoneRadius else { return nil }

        // atan2(dx, dy): 0 at 12 o'clock, +π/2 at 3 o'clock (clockwise) for y-up offsets.
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }

        // Sections are centered on their angle, so shift by half a section before bucketing.
        let bucket = Int(((angle + sectionWidth / 2) / sectionWidth).rounded(.down))
        return bucket % sectionCount
    }

    /// Whether the offset lies on the drawn ring (outside the dead zone, inside the outer radius if one is set).
    public func isWithinRing(dx: Double, dy: Double) -> Bool {
        guard dx.isFinite, dy.isFinite else { return false }
        let distance = hypot(dx, dy)
        guard distance >= deadZoneRadius else { return false }
        if let outerRadius { return distance <= outerRadius }
        return true
    }
}
