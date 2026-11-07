import Foundation

public struct ConfigSettings: Equatable, Sendable, Codable {
    public static let expandDelayRange = 0...1000
    public static let defaultExpandDelayMs = 120

    public var openMode: OpenMode
    /// Hover time on a group before its arc opens, in milliseconds. 0 opens it immediately.
    /// (`dwellMs` and `centerDwellMs` from older configs are ignored; see `ConfigLoader.notes`.)
    public private(set) var expandDelayMs: Int

    public init(openMode: OpenMode = .holdRelease, expandDelayMs: Int = defaultExpandDelayMs) {
        self.openMode = openMode
        self.expandDelayMs = min(max(expandDelayMs, Self.expandDelayRange.lowerBound), Self.expandDelayRange.upperBound)
    }

    public var expandDelay: TimeInterval { Double(expandDelayMs) / 1000 }

    private enum CodingKeys: String, CodingKey {
        case openMode, expandDelayMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            openMode: try container.decodeIfPresent(OpenMode.self, forKey: .openMode) ?? .holdRelease,
            expandDelayMs: try container.decodeIfPresent(Int.self, forKey: .expandDelayMs) ?? Self.defaultExpandDelayMs
        )
    }
}
