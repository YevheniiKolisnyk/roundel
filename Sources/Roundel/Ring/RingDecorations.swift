import RoundelCore
import SwiftUI

/// Hairlines between neighbouring items, shorter than the band is thick so they never touch its rims.
struct SeamsView: View {
    let band: RingBand
    let side: Double
    private let style = RingStyle.standard

    var body: some View {
        let middle = CGPoint(x: side / 2, y: side / 2)
        let from = band.innerRadius + style.seamInset
        let to = band.outerRadius - style.seamInset
        let seams = band.isFullCircle ? band.count : band.count - 1
        Path { path in
            guard band.count > 1, to > from else { return }
            for seam in 0..<seams {
                let angle = band.startAngle + Double(seam + (band.isFullCircle ? 0 : 1)) * band.itemWidth
                path.move(to: WedgeShape.point(center: middle, radius: from, angle: angle))
                path.addLine(to: WedgeShape.point(center: middle, radius: to, angle: angle))
            }
        }
        .stroke(Color.primary.opacity(style.seamOpacity), style: StrokeStyle(lineWidth: style.seamWidth, lineCap: .round))
        .frame(width: side, height: side)
    }
}

/// A thin rounded stem across the gap between a parent section and its arc.
struct ConnectorStem: View {
    let connector: BandModel.Connector
    let side: Double
    private let style = RingStyle.standard

    var body: some View {
        let middle = CGPoint(x: side / 2, y: side / 2)
        // Reach a little into both surfaces so the stem reads as joined to them.
        let inset = style.connectorWidth
        Path { path in
            path.move(to: WedgeShape.point(center: middle, radius: connector.innerRadius - inset, angle: connector.angle))
            path.addLine(to: WedgeShape.point(center: middle, radius: connector.outerRadius + inset, angle: connector.angle))
        }
        .stroke(Color.accentColor.opacity(style.connectorOpacity), style: StrokeStyle(lineWidth: style.connectorWidth, lineCap: .round))
        .frame(width: side, height: side)
    }
}

/// The middle: a small thin ring where the pointer starts, which gives way to the hovered item's name while there is
/// one. Both live in a fixed frame, so nothing around moves when the name appears, changes or goes.
struct CenterMark: View {
    let innerRadius: Double
    /// The hovered item's name (nil or empty: none).
    var title: String?
    var isDimmed = false

    private let style = RingStyle.standard
    private let info = SurfaceInfo()
    private let design = DesignMetrics.standard

    var body: some View {
        let name = (title ?? "").trimmingCharacters(in: .whitespaces)
        let fit = name.isEmpty ? nil : ContentFit.centerLabel(name, radius: innerRadius, style: style)
        let diameter = min(style.centerRingDiameter, max(0, innerRadius))
        let fade = design.resolve(design.ringHighlightMotion, reduceMotion: info.reduceMotion).animation
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(style.centerRingOpacity), lineWidth: style.centerRingWidth)
                .frame(width: diameter, height: diameter)
                .opacity(fit == nil ? 1 : 0)
            if let fit {
                // A soft backing, so the name reads on any desktop; only there while there is a name.
                Color.clear
                    .frame(width: max(0, 2 * innerRadius - 4), height: max(0, 2 * innerRadius - 4))
                    .roundelSurface(in: Circle(), casting: false)
                    .transition(.opacity)
                Text(name)
                    .font(.system(size: fit.fontSize, weight: .medium))
                    .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: fit.maxWidth)
                    .id(name)
                    .transition(.opacity)
            }
        }
        .frame(width: 2 * innerRadius, height: 2 * innerRadius)
        .animation(fade, value: name)
    }
}
