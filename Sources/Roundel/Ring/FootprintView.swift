import RoundelCore
import SwiftUI

/// Paints the ring's footprint with a nearly invisible fill. The window server decides which window gets a click
/// from the pixel alpha, so fully clear pixels (the gaps between wedges and bands, the dead zone) would let clicks
/// fall through to the app underneath. These pixels make the whole footprint belong to Roundel without being seen.
struct FootprintView: View {
    let regions: [RingFootprintRegion]

    /// Low enough to be invisible, high enough that the window server treats the pixel as part of the window.
    static let alpha = 0.01

    var body: some View {
        ZStack {
            ForEach(Array(regions.enumerated()), id: \.offset) { _, region in
                // Arcs start 1 pt inside their inner edge so neighbouring regions overlap instead of leaving a hairline seam.
                WedgeShape(startAngle: region.startAngle, endAngle: region.startAngle + region.sweep,
                           innerRadius: max(0, region.innerRadius - 1), outerRadius: region.outerRadius)
                    .fill(Color.black.opacity(Self.alpha))
            }
        }
        .transaction { $0.animation = nil }   // the footprint follows the layout immediately; only the wedges fade
    }
}
