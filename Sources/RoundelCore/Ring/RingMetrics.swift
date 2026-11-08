import Foundation

/// Every tunable number of the ring in one place. Change a value here (or on a copy, in tests) and the sizes,
/// hit-testing and timing follow. `RingMetrics.standard` is what the app uses.
public struct RingMetrics: Equatable, Sendable {
    public static let standard = RingMetrics()

    // Root ring
    /// Radius of the dead zone in the middle.
    public var deadZoneRadius = 30.0
    public var rootMinOuterRadius = 124.0
    public var rootMaxOuterRadius = 220.0
    /// Root icons sit this fraction of the way from the dead zone to the outer edge.
    public var rootIconRadiusFraction = 0.62

    // Arcs
    /// Empty space between two bands (where the connector is drawn). Unchanged on purpose: the arc closes when the
    /// pointer has been in the gap for `closeHysteresis`, so crossing time (and with it how slowly one may cross
    /// diagonally) is proportional to this number. Bigger cells do not need a bigger gap.
    public var bandGap = 8.0
    /// Radial thickness of an arc. A group cell reserves room for its chevron (`RingStyle.chevronClearance`) and still has
    /// to hold a four-letter format name turned sideways at 11 pt with the hover enlargement: 2 x (76 / 2 - 19) = 38 pt.
    public var bandThickness = 76.0
    /// Arc length each root item wants at its icon radius, in points (the root ring holds icons, mostly).
    public var minArcPerItem = 44.0
    /// Arc length each arc cell wants at its icon radius, in points. The labels of an arc are words ("WebP", "Convert"):
    /// seven Latin letters at the 11 pt floor with the 1.1 hover enlargement are about 49 pt; the cell's own insets (7 pt each side) and the turn of a cell towards the side take the rest.
    public var arcMinItemLength = 68.0
    /// A single item never gets wider than this (radians), so a couple of children do not become huge wedges.
    public var maxItemAngle = 55.0 * Double.pi / 180
    /// An arc never sweeps more than this (radians), so it cannot wrap around onto itself.
    public var maxArcSweep = 300.0 * Double.pi / 180
    /// Outermost radius an arc may grow to; past it the items tighten instead.
    /// Three arcs out from the root ring (the deepest the default config uses, plus one) fit within it.
    public var arcRadiusCap = 400.0

    // Timing
    /// How long the pointer must stay away from the open chain before its arcs close.
    public var closeHysteresis: TimeInterval = 0.15

    // Drawing and placement
    /// Room around the outermost band: glass draws a little beyond its shape (rim, refraction) and must not be cut.
    public var panelPadding = 12.0
    public var minIconSize = 12.0
    public var maxIconSize = 24.0
    /// Distance kept between an arc and the screen edge when shifting it on screen.
    public var edgeMargin = 12.0

    public init() {}

    // MARK: Sizing

    /// The root ring: a full circle that grows with the number of sections up to `maxOuterRadius`.
    public func rootBand(itemCount: Int, maxOuterRadius: Double? = nil) -> RingBand {
        let count = max(1, itemCount)
        let cap = max(rootMinOuterRadius, maxOuterRadius ?? rootMaxOuterRadius)

        let iconRadiusNeeded = minArcPerItem * Double(count) / (2 * .pi)
        let outerNeeded = deadZoneRadius + (iconRadiusNeeded - deadZoneRadius) / rootIconRadiusFraction
        let outer = min(max(rootMinOuterRadius, outerNeeded), cap)

        let iconRadius = deadZoneRadius + rootIconRadiusFraction * (outer - deadZoneRadius)
        let width = 2 * Double.pi / Double(count)
        return RingBand(
            level: 0, innerRadius: deadZoneRadius, outerRadius: outer,
            startAngle: -width / 2, itemWidth: width, count: count,
            iconRadius: iconRadius, iconSize: iconSize(arcLength: width * iconRadius),
            isCrowded: outerNeeded > outer + 0.5
        )
    }

    /// A child arc starting at `innerRadius`. With many children it first moves outward to make room, up to the cap;
    /// past the cap the items tighten (and the band is flagged crowded). The angular position is set later.
    public func arcBand(level: Int, itemCount: Int, innerRadius: Double, maxOuterRadius: Double? = nil) -> RingBand {
        let count = max(1, itemCount)
        let cap = maxOuterRadius ?? arcRadiusCap

        let midRadiusNeeded = arcMinItemLength * Double(count) / maxArcSweep
        var inner = max(innerRadius, midRadiusNeeded - bandThickness / 2)
        var outer = inner + bandThickness
        if outer > cap {
            outer = max(cap, innerRadius + bandThickness)   // never pulled inward of its natural spot
            inner = outer - bandThickness
        }

        let mid = (inner + outer) / 2
        var width = min(maxItemAngle, arcMinItemLength / mid)
        var crowded = false
        if width * Double(count) > maxArcSweep + 1e-9 {
            width = maxArcSweep / Double(count)
            crowded = true
        }
        return RingBand(
            level: level, innerRadius: inner, outerRadius: outer,
            startAngle: -width * Double(count) / 2, itemWidth: width, count: count,
            iconRadius: mid, iconSize: iconSize(arcLength: width * mid),
            isCrowded: crowded, exceedsRadiusCap: innerRadius + bandThickness > cap + 1e-9
        )
    }

    /// Side of the square panel that holds a ring reaching `outerRadius`. Even, so the center stays on a whole point.
    public func panelSide(forOuterRadius outerRadius: Double) -> Double {
        2 * (outerRadius + panelPadding).rounded(.up)
    }

    private func iconSize(arcLength: Double) -> Double {
        min(maxIconSize, max(minIconSize, arcLength * 0.55))
    }

    // MARK: Whole-config check

    public struct LevelWarning: Equatable, Sendable {
        public enum Kind: Sendable {
            /// More items than fit comfortably even at the size cap: regroup.
            case crowded
            /// The arc's natural position is beyond the radius cap: nested too deeply to fit on screen.
            case tooDeep
        }

        /// Group ids from the root; `[]` is the root ring.
        public let path: [String]
        public let count: Int
        public let kind: Kind
    }

    /// Every ring level that is too crowded, or nested too deeply, judged at the standard (not screen-limited) caps.
    public func levelWarnings(in config: RoundelConfig) -> [LevelWarning] {
        var result: [LevelWarning] = []

        func visit(_ nodes: [Node], path: [String], band: RingBand) {
            if band.isCrowded { result.append(LevelWarning(path: path, count: nodes.count, kind: .crowded)) }
            for node in nodes {
                guard let children = node.children else { continue }
                let childPath = path + [node.id]
                let arc = arcBand(level: band.level + 1, itemCount: children.count, innerRadius: band.outerRadius + bandGap)
                if arc.exceedsRadiusCap { result.append(LevelWarning(path: childPath, count: children.count, kind: .tooDeep)) }
                visit(children, path: childPath, band: arc)
            }
        }
        visit(config.ring, path: [], band: rootBand(itemCount: config.ring.count))
        return result
    }
}
