import RoundelCore
import SwiftUI

/// The selected item (or the open parent of an arc): an accent fill with a light edge and a soft glow just inside it.
/// Fades in and out; nothing is drawn for an unemphasised or disabled item.
struct ItemHighlight: View {
    let geometry: HighlightGeometry
    let emphasis: RingEmphasis
    let side: Double

    private let style = RingStyle.standard
    private let info = SurfaceInfo()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let traits = style.traits(for: emphasis, increaseContrast: info.increaseContrast, isDark: scheme == .dark)
        if traits.showsHighlight {
            let shape = RingBandShape(innerRadius: geometry.innerRadius, outerRadius: geometry.outerRadius,
                                      startAngle: geometry.startAngle, endAngle: geometry.endAngle, cornerRadius: geometry.cornerRadius)
            shape
                .fill(Color.accentColor.opacity(traits.fillOpacity))
                .overlay {
                    // Soft light along the inside of the edge: a blurred stroke cut off at the shape.
                    shape.stroke(Color.white.opacity(traits.glowOpacity), lineWidth: 8)
                        .blur(radius: 4)
                        .clipShape(shape)
                }
                .overlay { shape.strokeBorder(Color.white.opacity(traits.edgeOpacity), lineWidth: traits.edgeWidth) }
                .frame(width: side, height: side)
                .transition(.opacity)
        }
    }
}
