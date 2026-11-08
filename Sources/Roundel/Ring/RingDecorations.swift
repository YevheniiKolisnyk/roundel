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

/// A small thin ring in the middle, where the pointer starts. Not a disc: the middle stays open.
struct CenterMark: View {
    let innerRadius: Double
    private let style = RingStyle.standard

    var body: some View {
        Circle()
            .strokeBorder(Color.primary.opacity(style.centerRingOpacity), lineWidth: style.centerRingWidth)
            .frame(width: min(style.centerRingDiameter, max(0, innerRadius)), height: min(style.centerRingDiameter, max(0, innerRadius)))
    }
}
