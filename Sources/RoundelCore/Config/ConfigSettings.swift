import Foundation

public struct ConfigSettings: Equatable, Sendable, Codable {
    public static let dwellRange = 100...1000
    public static let defaultDwellMs = 250

    public var openMode: OpenMode
    /// Hover time on a group before its child ring opens (hover mode only).
    public private(set) var dwellMs: Int
    /// Hover time in the center before going back one level (hover mode only).
    public private(set) var centerDwellMs: Int

    public init(openMode: OpenMode = .holdRelease,
                dwellMs: Int = defaultDwellMs,
                centerDwellMs: Int = defaultDwellMs) {
        self.openMode = openMode
        self.dwellMs = Self.clamp(dwellMs)
        self.centerDwellMs = Self.clamp(centerDwellMs)
    }

    public var dwell: TimeInterval { Double(dwellMs) / 1000 }
    public var centerDwell: TimeInterval { Double(centerDwellMs) / 1000 }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, dwellRange.lowerBound), dwellRange.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case openMode, dwellMs, centerDwellMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            openMode: try container.decodeIfPresent(OpenMode.self, forKey: .openMode) ?? .holdRelease,
            dwellMs: try container.decodeIfPresent(Int.self, forKey: .dwellMs) ?? Self.defaultDwellMs,
            centerDwellMs: try container.decodeIfPresent(Int.self, forKey: .centerDwellMs) ?? Self.defaultDwellMs
        )
    }
}
