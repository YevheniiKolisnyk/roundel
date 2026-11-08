import RoundelCore
import SwiftUI

/// The selected item (or the open parent of an arc): an accent fill, a light edge and a soft glow just inside it.
/// Everything is drawn in one sector shape and clipped to exactly that shape, so the silhouette is the sector's and
/// nothing can reach outside it; the glow is a few stacked inner strokes, not a blur. Always present: an item that
/// is not emphasised is drawn with zero strength, so changing the emphasis is a quick cross-fade, never a morph.
struct ItemHighlight: View {
    let geometry: HighlightGeometry
    let emphasis: RingEmphasis
    let side: Double

    private let style = RingStyle.standard
    private let info = SurfaceInfo()
    private let design = DesignMetrics.standard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let traits = style.traits(for: emphasis, increaseContrast: info.increaseContrast, isDark: scheme == .dark)
        let shape = RingBandShape(innerRadius: geometry.innerRadius, outerRadius: geometry.outerRadius,
                                  startAngle: geometry.startAngle, endAngle: geometry.endAngle, cornerRadius: geometry.cornerRadius)
        ZStack {
            shape.fill(Color.accentColor.opacity(traits.fillOpacity))
            // Soft light along the inside of the edge: strokes centered on the outline, of which the clip keeps the
            // inner half, widest and faintest first.
            ForEach([12.0, 8.0, 4.0], id: \.self) { width in
                shape.stroke(Color.white.opacity(traits.glowOpacity / 3), lineWidth: traits.glowOpacity > 0 ? width : 0)
            }
            shape.stroke(Color.white.opacity(traits.edgeOpacity), lineWidth: traits.edgeWidth * 2)
        }
        .clipShape(shape)
        .animation(design.resolve(design.ringHighlightMotion, reduceMotion: info.reduceMotion).animation, value: emphasis)
        .frame(width: side, height: side)
    }
}
