import Observation
import RoundelCore

struct DisplayItem: Identifiable {
    let item: RingItem
    let icon: ResolvedIcon
    var id: String { item.id }
}

/// View state for the ring. The panel is reused between openings, so this is updated in place.
@MainActor
@Observable
final class RingModel {
    var items: [DisplayItem] = []
    var metrics = RingMetrics.make(sectionCount: 1)
    var highlighted: Int?
    /// 0...1 while a group (or the center) is being dwelled on.
    var dwellProgress: Double?
    /// How many groups deep the visible ring is. Greater than 0 shows the "back" mark in the center.
    var depth = 0
    /// Changes whenever the visible ring is swapped, so the view can cross-fade.
    var levelToken = 0
}
