/// One slot in the ring. Milestone 1 only has placeholders; later milestones build these from config + registry.
public struct RingSection: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    /// SF Symbol name.
    public let symbol: String

    public init(id: Int, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

public enum PlaceholderRing {
    public static let minCount = 2
    public static let maxCount = 24
    public static let defaultCount = 6

    public static func clampedCount(_ count: Int) -> Int {
        min(max(count, minCount), maxCount)
    }

    public static func sections(count: Int) -> [RingSection] {
        (0..<clampedCount(count)).map { index in
            RingSection(id: index, title: "\(index + 1)", symbol: "\(index + 1).circle")
        }
    }
}
