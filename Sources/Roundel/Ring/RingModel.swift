import Observation
import RoundelCore

/// View state for the ring. The panel is reused between openings, so this is updated in place.
@MainActor
@Observable
final class RingModel {
    var sections: [RingSection] = []
    var highlighted: Int?
}
