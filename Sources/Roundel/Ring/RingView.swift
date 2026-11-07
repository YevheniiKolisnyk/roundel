import RoundelCore
import SwiftUI

struct RingView: View {
    let model: RingModel

    private let gap: Double = 2.5 * .pi / 180

    var body: some View {
        let geometry = RingLayout.geometry(sectionCount: model.sections.count)
        let half = geometry.sectionWidth / 2

        ZStack {
            ForEach(model.sections) { section in
                let center = geometry.centerAngle(ofSection: section.id)
                let isHighlighted = model.highlighted == section.id
                // A single section would make a full circle; the gap would leave a seam, so skip it then.
                let inset = model.sections.count > 1 ? gap / 2 : 0

                WedgeShape(
                    startAngle: center - half + inset,
                    endAngle: center + half - inset,
                    innerRadius: RingLayout.deadZoneRadius,
                    outerRadius: RingLayout.outerRadius
                )
                .fill(isHighlighted ? AnyShapeStyle(Color.accentColor.opacity(0.9)) : AnyShapeStyle(.regularMaterial))
                .overlay {
                    WedgeShape(
                        startAngle: center - half + inset,
                        endAngle: center + half - inset,
                        innerRadius: RingLayout.deadZoneRadius,
                        outerRadius: RingLayout.outerRadius
                    )
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }

                label(for: section, angle: center, highlighted: isHighlighted)
            }

            Circle()
                .fill(.regularMaterial)
                .frame(width: RingLayout.deadZoneRadius * 2 - 8, height: RingLayout.deadZoneRadius * 2 - 8)
                .opacity(0.6)
        }
        .frame(width: RingLayout.panelSide, height: RingLayout.panelSide)
        .animation(.easeOut(duration: 0.08), value: model.highlighted)
        .allowsHitTesting(false)
    }

    private func label(for section: RingSection, angle: Double, highlighted: Bool) -> some View {
        let radius = (RingLayout.deadZoneRadius + RingLayout.outerRadius) / 2
        let side = RingLayout.panelSide
        let point = WedgeShape.point(center: CGPoint(x: side / 2, y: side / 2), radius: radius, angle: angle)

        return Image(systemName: section.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .position(point)
    }
}
