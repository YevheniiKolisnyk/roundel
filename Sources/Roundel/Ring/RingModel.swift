import Observation
import RoundelCore

struct DisplayItem: Identifiable {
    let item: RingItem
    let icon: ResolvedIcon
    var id: String { item.id }
}

/// One visible band (the root ring or an arc) with what the view needs to draw it.
struct BandModel: Identifiable {
    /// The short stub between a parent section and its arc.
    struct Connector {
        let angle: Double
        let width: Double
        let innerRadius: Double
        let outerRadius: Double
        let parentID: String
    }

    let band: RingBand
    let items: [DisplayItem]
    let connector: Connector?

    /// Stable across layout changes, so SwiftUI animates arcs in and out instead of redrawing everything.
    var id: String { connector.map { "\(band.level):\($0.parentID)" } ?? "root" }
}

/// View state for the ring. The panel is reused between openings, so this is updated in place.
@MainActor
@Observable
final class RingModel {
    var bands: [BandModel] = []
    /// The item under the pointer.
    var hovered: RingItemRef?
    /// The groups whose arcs are open.
    var openParents: Set<RingItemRef> = []
    var panelSide = 0.0
    /// The area the ring owns on screen, gaps included (see `RingLayout.footprint`).
    var footprint: [RingFootprintRegion] = []
    /// Whether the ring's visuals are shown (they appear with a short animation after the panel is up). Only paint:
    /// the footprint and all hit-testing work from the first frame whatever this is.
    var isPresented = false
}
