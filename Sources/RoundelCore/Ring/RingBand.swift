import Foundation

/// What is under the pointer, found by polar hit-testing: the radius picks the band, the angle picks the item.
public enum RingHit: Equatable, Sendable {
    /// The dead zone in the middle.
    case center
    case item(level: Int, index: Int)
    /// Between bands, or inside a band's radius but outside the angular extent of its arc: nothing there.
    case gap
    /// Beyond the outermost band (or invalid input).
    case outside
}

/// One concentric band of items: the root ring (a full circle) or a child arc around the parent's angle.
/// Angles are radians, clockwise from 12 o'clock.
public struct RingBand: Equatable, Sendable {
    public let level: Int
    public let innerRadius: Double
    public let outerRadius: Double
    /// Leading (counter-clockwise) edge of item 0.
    public let startAngle: Double
    /// Angular width of every item.
    public let itemWidth: Double
    public let count: Int
    public let iconRadius: Double
    public let iconSize: Double
    /// True when the cap stopped the band from giving every item its minimum arc length.
    public let isCrowded: Bool
    /// True when even the band's natural position lies beyond the radius cap (very deep nesting).
    public let exceedsRadiusCap: Bool

    public init(level: Int, innerRadius: Double, outerRadius: Double, startAngle: Double, itemWidth: Double, count: Int,
                iconRadius: Double, iconSize: Double, isCrowded: Bool, exceedsRadiusCap: Bool = false) {
        self.level = level
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.startAngle = startAngle
        self.itemWidth = itemWidth
        self.count = count
        self.iconRadius = iconRadius
        self.iconSize = iconSize
        self.isCrowded = isCrowded
        self.exceedsRadiusCap = exceedsRadiusCap
    }

    public var sweep: Double { itemWidth * Double(count) }
    public var isFullCircle: Bool { sweep >= 2 * .pi - 1e-9 }

    public func centerAngle(ofItem index: Int) -> Double {
        startAngle + (Double(index) + 0.5) * itemWidth
    }

    /// The same band rotated so that the middle of its arc faces `angle`.
    public func centered(on angle: Double) -> RingBand {
        RingBand(level: level, innerRadius: innerRadius, outerRadius: outerRadius, startAngle: angle - sweep / 2,
                 itemWidth: itemWidth, count: count, iconRadius: iconRadius, iconSize: iconSize,
                 isCrowded: isCrowded, exceedsRadiusCap: exceedsRadiusCap)
    }

    /// Item at `angle`, or `nil` when the angle is outside the arc.
    public func itemIndex(forAngle angle: Double) -> Int? {
        guard count > 0, itemWidth > 0, angle.isFinite else { return nil }
        var delta = (angle - startAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if delta < 0 { delta += 2 * .pi }
        if !isFullCircle && delta >= sweep { return nil }
        return min(Int(delta / itemWidth), count - 1)
    }
}
