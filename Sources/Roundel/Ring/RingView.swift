import RoundelCore
import SwiftUI

struct RingView: View {
    let model: RingModel

    var body: some View {
        let metrics = model.metrics
        let geometry = metrics.geometry
        let half = geometry.sectionWidth / 2
        let count = model.items.count
        // Visual gap between wedges, but never more than a fifth of a wedge.
        let gap = min(2.5 * .pi / 180, geometry.sectionWidth * 0.2)
        let inset = count > 1 ? gap / 2 : 0   // a single wedge is a full circle: no seam
        let side = metrics.panelSide

        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, display in
                let center = geometry.centerAngle(ofSection: index)
                let isHighlighted = model.highlighted == index
                let wedge = WedgeShape(
                    startAngle: center - half + inset,
                    endAngle: center + half - inset,
                    innerRadius: metrics.deadZoneRadius,
                    outerRadius: metrics.outerRadius
                )

                wedge
                    .fill(isHighlighted ? AnyShapeStyle(Color.accentColor.opacity(0.9)) : AnyShapeStyle(.regularMaterial))
                    .overlay { wedge.stroke(.white.opacity(0.18), lineWidth: 0.5) }
                    .overlay {
                        if isHighlighted, display.item.isGroup, let progress = model.dwellProgress {
                            // Dwell progress: the wedge fills from the center outwards.
                            WedgeShape(
                                startAngle: center - half + inset,
                                endAngle: center + half - inset,
                                innerRadius: metrics.deadZoneRadius,
                                outerRadius: metrics.deadZoneRadius + (metrics.outerRadius - metrics.deadZoneRadius) * progress
                            )
                            .fill(.white.opacity(0.25))
                        }
                    }
                    .opacity(display.item.isDimmed ? 0.4 : 1)

                IconView(icon: display.icon, size: metrics.iconSize, color: isHighlighted ? .white : .primary)
                    .opacity(display.item.isDimmed ? 0.4 : 1)
                    .position(WedgeShape.point(center: CGPoint(x: side / 2, y: side / 2), radius: metrics.iconRadius, angle: center))

                if display.item.isGroup {
                    // Chevron near the outer edge, pointing outwards: "this opens a sub-ring".
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
                        .rotationEffect(.radians(center))
                        .position(WedgeShape.point(center: CGPoint(x: side / 2, y: side / 2), radius: metrics.outerRadius - 9, angle: center))
                }
            }

            centerMark(metrics: metrics)
        }
        .id(model.levelToken)
        .transition(.opacity)
        .frame(width: side, height: side)
        .animation(.easeOut(duration: 0.08), value: model.highlighted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func centerMark(metrics: RingMetrics) -> some View {
        let diameter = metrics.deadZoneRadius * 2 - 8
        return ZStack {
            Circle().fill(.regularMaterial).opacity(0.6)
            if model.depth > 0 {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                if model.highlighted == nil, let progress = model.dwellProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }
            }
        }
        .frame(width: diameter, height: diameter)
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
