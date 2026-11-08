import RoundelCore
import SwiftUI

/// A point of the appear animation, used to draw a single frame of it (tests, renders). Not used in the app.
struct AppearFrame: Equatable {
    var ring: Double
    var arcs: Double
    static let shown = AppearFrame(ring: 1, arcs: 1)
}

/// Opacity and a small scale of an already laid-out view, nothing else. The animation is scoped to those two values
/// (`animation(_:body:)`), so whatever else changes in the same update (sizes, positions, the panel growing) snaps
/// instead of animating along with them.
struct RingAppear: ViewModifier {
    var progress: Double
    var minScale: Double
    var anchor: UnitPoint
    var animation: Animation?

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .animation(animation) { view in
                view.opacity(progress).scaleEffect(minScale + (1 - minScale) * progress, anchor: anchor)
            }
    }
}

/// The ring: an invisible footprint under the visuals. The footprint (and with it all hit-testing, which is polar and
/// lives in `RingLayout`) is there from the first frame; the visuals come in with a short fade and a small scale, or a
/// plain cross-fade under Reduce Motion.
struct RingView: View {
    let model: RingModel
    /// Draws one frame of the appearance instead of animating it (tests and renders only).
    var frozen: AppearFrame?
    private let info = SurfaceInfo()
    private let style = RingStyle.standard
    private let design = DesignMetrics.standard

    var body: some View {
        let side = model.panelSide
        let motion = design.resolve(design.ringAppearMotion, reduceMotion: info.reduceMotion).animation
        ZStack {
            FootprintView(regions: model.footprint)
            RingVisuals(model: model, frozen: frozen)
                .modifier(RingAppear(progress: frozen?.ring ?? (model.isPresented ? 1 : 0),
                                     minScale: info.reduceMotion ? 1 : style.appearScale,
                                     anchor: .center,
                                     animation: frozen == nil ? motion : nil))
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// All bands plus the center mark.
private struct RingVisuals: View {
    let model: RingModel
    let frozen: AppearFrame?
    private let info = SurfaceInfo()
    private let style = RingStyle.standard

    var body: some View {
        let side = model.panelSide
        ZStack {
            ForEach(model.bands) { bandModel in
                if let connector = bandModel.connector {
                    ArcAppearing(frozen: frozen?.arcs, anchor: anchor(of: connector, side: side),
                                 minScale: info.reduceMotion ? 1 : style.arcAppearScale) {
                        BandView(bandModel: bandModel, hovered: model.hovered, openParents: model.openParents, side: side)
                    }
                } else {
                    BandView(bandModel: bandModel, hovered: model.hovered, openParents: model.openParents, side: side)
                }
            }
            if let root = model.bands.first {
                CenterMark(innerRadius: root.band.innerRadius, title: model.hoveredItem?.item.title, isDimmed: model.hoveredItem?.item.isDimmed ?? false)
            }
        }
    }

    /// An arc grows out of its parent section: its anchor is the point on the parent's outer edge.
    private func anchor(of connector: BandModel.Connector, side: Double) -> UnitPoint {
        let origin = WedgeShape.point(center: .zero, radius: connector.outerRadius, angle: connector.angle)
        return UnitPoint(x: 0.5 + origin.x / side, y: 0.5 + origin.y / side)
    }
}

/// An arc fades and scales in from its parent's anchor the first time it is shown. Later layout changes of the same arc
/// (it slides, its parent moves) do not replay it.
private struct ArcAppearing<Content: View>: View {
    let frozen: Double?
    let anchor: UnitPoint
    let minScale: Double
    @ViewBuilder let content: Content
    @State private var shown = false
    private let info = SurfaceInfo()
    private let design = DesignMetrics.standard

    var body: some View {
        content
            .modifier(RingAppear(progress: frozen ?? (shown ? 1 : 0), minScale: minScale, anchor: anchor,
                                 animation: frozen == nil ? design.resolve(design.ringAppearMotion, reduceMotion: info.reduceMotion).animation : nil))
            .onAppear { shown = true }
    }
}

/// One band: a single continuous surface, hairline separators, the selected item's highlight, then icons.
private struct BandView: View {
    let bandModel: BandModel
    let hovered: RingItemRef?
    let openParents: Set<RingItemRef>
    let side: Double

    private let style = RingStyle.standard
    private var band: RingBand { bandModel.band }

    var body: some View {
        let shape = RingBandShape.of(band, style: style)
        ZStack {
            Color.clear
                .frame(width: side, height: side)
                .roundelSurface(in: shape, casting: false)

            if let connector = bandModel.connector {
                ConnectorStem(connector: connector, side: side)
            }
            SeamsView(band: band, side: side)

            ForEach(Array(bandModel.items.enumerated()), id: \.element.id) { index, display in
                let ref = RingItemRef(level: band.level, index: index)
                let emphasis = style.emphasis(isHovered: hovered == ref, isOpenParent: openParents.contains(ref), isDisabled: display.item.isDimmed)
                ItemHighlight(geometry: style.highlightGeometry(for: band, index: index), emphasis: emphasis, side: side)
                ItemContent(display: display, band: band, index: index, emphasis: emphasis, side: side)
            }
        }
    }
}

extension RingBandShape {
    /// The outline of a whole band.
    static func of(_ band: RingBand, style: RingStyle) -> RingBandShape {
        let sweep = band.isFullCircle ? 2 * Double.pi : band.itemWidth * Double(band.count)
        let mid = max(1, (band.innerRadius + band.outerRadius) / 2)
        return RingBandShape(
            innerRadius: band.innerRadius, outerRadius: band.outerRadius,
            startAngle: band.startAngle, endAngle: band.startAngle + sweep,
            cornerRadius: style.cornerRadius(thickness: band.outerRadius - band.innerRadius, arcLength: sweep * mid, preferred: style.bandCornerRadius),
            isFullCircle: band.isFullCircle
        )
    }
}
