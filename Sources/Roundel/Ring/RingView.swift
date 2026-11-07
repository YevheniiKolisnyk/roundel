import RoundelCore
import SwiftUI

struct RingView: View {
    let model: RingModel

    var body: some View {
        let side = model.panelSide
        ZStack {
            ForEach(model.bands) { bandModel in
                BandView(bandModel: bandModel, highlighted: model.highlighted, side: side)
                    .transition(.opacity)
            }
            if let root = model.bands.first {
                CenterMark(radius: root.band.innerRadius)
            }
        }
        .frame(width: side, height: side)
        .animation(.easeOut(duration: 0.08), value: model.highlighted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct BandView: View {
    let bandModel: BandModel
    let highlighted: Set<RingItemRef>
    let side: Double

    private var band: RingBand { bandModel.band }
    private var middle: CGPoint { CGPoint(x: side / 2, y: side / 2) }

    var body: some View {
        // Visual gap between wedges, never more than a fifth of a wedge; a lone full-circle wedge has no seam.
        let gap = min(2.5 * .pi / 180, band.itemWidth * 0.2)
        let inset = (band.isFullCircle && band.count == 1) ? 0 : gap / 2

        ZStack {
            if let connector = bandModel.connector {
                ConnectorStub(connector: connector)
            }
            ForEach(Array(bandModel.items.enumerated()), id: \.element.id) { index, display in
                ItemView(
                    display: display,
                    band: band,
                    index: index,
                    inset: inset,
                    isHighlighted: highlighted.contains(RingItemRef(level: band.level, index: index)),
                    middle: middle
                )
            }
        }
    }
}

private struct ItemView: View {
    let display: DisplayItem
    let band: RingBand
    let index: Int
    let inset: Double
    let isHighlighted: Bool
    let middle: CGPoint

    var body: some View {
        let center = band.centerAngle(ofItem: index)
        let half = band.itemWidth / 2
        let wedge = WedgeShape(startAngle: center - half + inset, endAngle: center + half - inset,
                               innerRadius: band.innerRadius, outerRadius: band.outerRadius)
        let iconPoint = WedgeShape.point(center: middle, radius: band.iconRadius, angle: center)
        let dim = display.item.isDimmed ? 0.4 : 1.0

        ZStack {
            wedge
                .fill(isHighlighted ? AnyShapeStyle(Color.accentColor.opacity(0.9)) : AnyShapeStyle(.regularMaterial))
                .overlay { wedge.stroke(.white.opacity(0.18), lineWidth: 0.5) }
                .opacity(dim)

            IconView(icon: display.icon, size: band.iconSize, color: isHighlighted ? .white : .primary)
                .opacity(dim)
                .position(iconPoint)

            if display.item.isActive == true {
                // Toggle is currently on (caffeinate, dark mode, mute).
                Circle()
                    .fill(Color.green)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .position(x: iconPoint.x + band.iconSize * 0.62, y: iconPoint.y - band.iconSize * 0.62)
            }

            if display.item.isGroup {
                // Chevron near the outer edge, pointing outwards: "this opens an arc".
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
                    .rotationEffect(.radians(center))
                    .position(WedgeShape.point(center: middle, radius: band.outerRadius - 9, angle: center))
            }
        }
    }
}

/// A subtle bridge across the gap between the parent section and the start of its arc.
private struct ConnectorStub: View {
    let connector: BandModel.Connector

    var body: some View {
        let width = min(connector.width * 0.4, 9 * .pi / 180)
        WedgeShape(startAngle: connector.angle - width / 2, endAngle: connector.angle + width / 2,
                   innerRadius: connector.innerRadius - 1, outerRadius: connector.outerRadius + 1)
            .fill(Color.accentColor.opacity(0.55))
    }
}

private struct CenterMark: View {
    let radius: Double

    var body: some View {
        Circle()
            .fill(.regularMaterial)
            .opacity(0.6)
            .frame(width: radius * 2 - 8, height: radius * 2 - 8)
    }
}

private struct IconView: View {
    let icon: ResolvedIcon
    let size: Double
    let color: Color

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
        case .emoji(let value):
            Text(value)
                .font(.system(size: size))
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.15, height: size * 1.15)
        case .letter(let letter):
            Text(letter)
                .font(.system(size: size * 0.95, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}
