import Foundation

public struct RoundelConfig: Equatable, Sendable, Codable {
    public static let supportedVersion = 1

    public var version: Int
    public var settings: ConfigSettings
    public var ring: [Node]

    public init(version: Int = RoundelConfig.supportedVersion, settings: ConfigSettings = ConfigSettings(), ring: [Node]) {
        self.version = version
        self.settings = settings
        self.ring = ring
    }

    private enum CodingKeys: String, CodingKey {
        case version, settings, ring
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        settings = try container.decodeIfPresent(ConfigSettings.self, forKey: .settings) ?? ConfigSettings()
        ring = try container.decode([Node].self, forKey: .ring)
    }

    // MARK: Lookup

    /// The ring shown after entering the groups in `path` (group ids, outermost first). `[]` is the root ring.
    public func nodes(at path: [String]) -> [Node]? {
        var level = ring
        for id in path {
            guard let group = level.first(where: { $0.id == id }), let children = group.children else { return nil }
            level = children
        }
        return level
    }

    public func node(withID id: String) -> Node? {
        func search(_ nodes: [Node]) -> Node? {
            for node in nodes {
                if node.id == id { return node }
                if let children = node.children, let found = search(children) { return found }
            }
            return nil
        }
        return search(ring)
    }
}
