import Foundation

/// The root ring plus the arcs of the groups that are currently open, with polar hit-testing. Pure and deterministic.
public struct RingLayout: Equatable, Sendable {
    public let bands: [RingBand]
    public let deadZoneRadius: Double

    public var outerRadius: Double { bands.last?.outerRadius ?? deadZoneRadius }

    public func hit(dx: Double, dy: Double) -> RingHit {
        guard dx.isFinite, dy.isFinite else { return .outside }
        let radius = hypot(dx, dy)
        if radius < deadZoneRadius { return .center }

        for band in bands where radius >= band.innerRadius && radius <= band.outerRadius {
            // atan2(dx, dy): 0 at 12 o'clock, +π/2 at 3 o'clock, for y-up offsets.
            if let index = band.itemIndex(forAngle: atan2(dx, dy)) { return .item(level: band.level, index: index) }
            return .gap
        }
        return radius > outerRadius ? .outside : .gap
    }

    /// Builds the layout for the groups in `path` (ids, outermost first). Stops at the first id that is not a group.
    /// - Parameters:
    ///   - rootMaxOuterRadius / arcMaxOuterRadius: screen-derived caps; `nil` uses the values in `metrics`.
    ///   - placement: when given, each arc is shifted along its band to stay on screen.
    public static func make(
        root: [Node],
        path: [String],
        metrics: RingMetrics = .standard,
        rootMaxOuterRadius: Double? = nil,
        arcMaxOuterRadius: Double? = nil,
        placement: ArcPlacement.Context? = nil
    ) -> RingLayout {
        var bands = [metrics.rootBand(itemCount: root.count, maxOuterRadius: rootMaxOuterRadius)]
        var nodes = root

        for id in path {
            guard let parent = bands.last,
                  let index = nodes.firstIndex(where: { $0.id == id }),
                  let children = nodes[index].children else { break }

            let arc = metrics.arcBand(
                level: bands.count,
                itemCount: children.count,
                innerRadius: parent.outerRadius + metrics.bandGap,
                maxOuterRadius: arcMaxOuterRadius
            )
            let desired = parent.centerAngle(ofItem: index)
            var center = desired
            if let placement {
                center = ArcPlacement.centerAngle(
                    desired: desired, sweep: arc.sweep, itemWidth: arc.itemWidth,
                    innerRadius: arc.innerRadius, outerRadius: arc.outerRadius,
                    ringCenter: placement.ringCenter, bounds: placement.bounds, margin: metrics.edgeMargin
                )
            }
            bands.append(arc.centered(on: center))
            nodes = children
        }
        return RingLayout(bands: bands, deadZoneRadius: metrics.deadZoneRadius)
    }
}
