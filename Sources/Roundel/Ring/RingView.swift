import RoundelCore
import SwiftUI

/// The ring: an invisible footprint under the visuals. The footprint (and with it all hit-testing, which is polar and
/// lives in `RingLayout`) is there from the first frame; only the visuals appear with an animation, or a cross-fade
/// under Reduce Motion.
struct RingView: View {
    let model: RingModel
    private let info = SurfaceInfo()
    private let style = RingStyle.standard

    var body: some View {
        let side = model.panelSide
        ZStack {
            FootprintView(regions: model.footprint)
            if model.isPresented {
                RingVisuals(model: model)
                    .transition(info.reduceMotion ? .opacity : .scale(scale: style.appearScale).combined(with: .opacity))
            }
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// All bands plus the center mark.
private struct RingVisuals: View {
    let model: RingModel
    private let info = SurfaceInfo()
    private let style = RingStyle.standard
    private let design = DesignMetrics.standard

    var body: some View {
        let side = model.panelSide
        let selection = design.resolve(design.selectionMotion, reduceMotion: info.reduceMotion).animation
        ZStack {
            ForEach(model.bands) { bandModel in
                BandView(bandModel: bandModel, hovered: model.hovered, openParents: model.openParents, side: side)
                    .transition(arcTransition(for: bandModel, side: side))
            }
            if let root = model.bands.first {
                CenterMark(innerRadius: root.band.innerRadius)
            }
        }
        .animation(selection, value: model.hovered)
        .animation(selection, value: model.openParents)
    }

    /// An arc grows out of its parent section; with Reduce Motion it just fades.
    private func arcTransition(for bandModel: BandModel, side: Double) -> AnyTransition {
        guard !info.reduceMotion, let connector = bandModel.connector else { return .opacity }
        let origin = WedgeShape.point(center: .zero, radius: connector.outerRadius, angle: connector.angle)
        let anchor = UnitPoint(x: 0.5 + origin.x / side, y: 0.5 + origin.y / side)
        return .scale(scale: style.arcAppearScale, anchor: anchor).combined(with: .opacity)
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
