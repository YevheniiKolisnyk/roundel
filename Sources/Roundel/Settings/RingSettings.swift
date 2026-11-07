import Foundation
import RoundelCore

/// Temporary UserDefaults-backed settings (milestone 1 scaffolding).
/// Moves to the JSON config in milestone 2 and to a real settings UI later.
@MainActor
final class RingSettings {
    private enum Key {
        static let openMode = "openMode"
        static let sectionCount = "sectionCount"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var openMode: OpenMode {
        get { defaults.string(forKey: Key.openMode).flatMap(OpenMode.init(rawValue:)) ?? .holdRelease }
        set { defaults.set(newValue.rawValue, forKey: Key.openMode) }
    }

    var sectionCount: Int {
        get {
            let stored = defaults.object(forKey: Key.sectionCount) as? Int
            return PlaceholderRing.clampedCount(stored ?? PlaceholderRing.defaultCount)
        }
        set { defaults.set(PlaceholderRing.clampedCount(newValue), forKey: Key.sectionCount) }
    }
}
