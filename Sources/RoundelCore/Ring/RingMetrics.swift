import Foundation

/// Sizes of one ring level. The ring grows with the number of sections so icons keep room, up to a cap
/// (so it never outgrows the screen); beyond that the wedges simply get tighter.
public struct RingMetrics: Equatable, Sendable {
    public static let deadZoneRadius = 30.0
    public static let minOuterRadius = 124.0
    public static let defaultMaxOuterRadius = 220.0
    /// Arc length each icon wants at the icon radius, in points.
    public static let minArcPerSection = 44.0
    public static let panelPadding = 4.0
    /// Icons sit this fraction of the way from the dead zone to the outer edge.
    public static let iconRadiusFraction = 0.62

    public let sectionCount: Int
    public let deadZoneRadius: Double
    public let outerRadius: Double
    public let iconRadius: Double
    public let iconSize: Double
    /// True when the cap stopped the ring from growing enough, so wedges are tighter than `minArcPerSection`.
    public let isCrowded: Bool

    /// Side of the square panel, an even integer so the ring center stays on a whole point.
    public var panelSide: Double { 2 * (outerRadius + Self.panelPadding).rounded(.up) }

    public var geometry: RingGeometry {
        RingGeometry(sectionCount: sectionCount, deadZoneRadius: deadZoneRadius, outerRadius: outerRadius)
    }

    public static func make(sectionCount: Int, maxOuterRadius: Double = defaultMaxOuterRadius) -> RingMetrics {
        let count = max(1, sectionCount)
        let dead = deadZoneRadius
        let cap = max(minOuterRadius, maxOuterRadius)

        let iconRadiusNeeded = minArcPerSection * Double(count) / (2 * .pi)
        let outerNeeded = dead + (iconRadiusNeeded - dead) / iconRadiusFraction
        let outer = min(max(minOuterRadius, outerNeeded), cap)

        let iconRadius = dead + iconRadiusFraction * (outer - dead)
        let arc = 2 * .pi * iconRadius / Double(count)
        let iconSize = min(24, max(12, arc * 0.55))

        return RingMetrics(
            sectionCount: count,
            deadZoneRadius: dead,
            outerRadius: outer,
            iconRadius: iconRadius,
            iconSize: iconSize,
            isCrowded: outerNeeded > outer + 0.5
        )
    }

    // MARK: Whole-config check

    public struct CrowdedLevel: Equatable, Sendable {
        /// Group ids from the root; `[]` is the root ring.
        public let path: [String]
        public let count: Int
    }

    /// Every ring level that has more sections than fit comfortably at the size cap.
    public static func crowdedLevels(in config: RoundelConfig, maxOuterRadius: Double = defaultMaxOuterRadius) -> [CrowdedLevel] {
        var result: [CrowdedLevel] = []
        func visit(_ nodes: [Node], path: [String]) {
            if make(sectionCount: nodes.count, maxOuterRadius: maxOuterRadius).isCrowded {
                result.append(CrowdedLevel(path: path, count: nodes.count))
            }
            for node in nodes {
                if let children = node.children { visit(children, path: path + [node.id]) }
            }
        }
        visit(config.ring, path: [])
        return result
    }
}
