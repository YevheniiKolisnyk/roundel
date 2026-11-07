import Foundation

/// One annular sector the ring owns on screen. Angles are radians, clockwise from 12 o'clock, like `RingBand`.
public struct RingFootprintRegion: Equatable, Sendable {
    public let innerRadius: Double
    public let outerRadius: Double
    public let startAngle: Double
    public let sweep: Double

    public var isFullCircle: Bool { sweep >= 2 * .pi - 1e-9 }

    public func contains(dx: Double, dy: Double) -> Bool {
        guard dx.isFinite, dy.isFinite else { return false }
        let radius = hypot(dx, dy)
        guard radius >= innerRadius, radius <= outerRadius else { return false }
        if isFullCircle { return true }

        var delta = (atan2(dx, dy) - startAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if delta < 0 { delta += 2 * .pi }
        return delta <= sweep
    }
}

extension RingLayout {
    /// The area that must receive mouse events, gaps included, so a click there never reaches the app underneath.
    /// - The root: the whole disc from the center out, dead zone included.
    /// - Each open arc: from its first item's start angle to its last item's end angle, radially from the previous
    ///   band's outer edge (so the bridging gap is included) to its own outer edge.
    /// The empty angular space beyond the ends of an arc is not part of it and stays click-through.
    public var footprint: [RingFootprintRegion] {
        var regions: [RingFootprintRegion] = []
        var previousOuter = 0.0
        for band in bands {
            regions.append(RingFootprintRegion(
                innerRadius: previousOuter,
                outerRadius: band.outerRadius,
                startAngle: band.startAngle,
                sweep: band.level == 0 ? 2 * .pi : band.sweep
            ))
            previousOuter = band.outerRadius
        }
        return regions
    }

    public func footprintContains(dx: Double, dy: Double) -> Bool {
        footprint.contains { $0.contains(dx: dx, dy: dy) }
    }
}
