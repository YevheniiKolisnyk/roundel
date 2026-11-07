import Foundation

/// An action leaf. `action` is a free-form string in M2 (log-only stub). In M3 an id missing from the registry is a
/// runtime warning (node shown dimmed), never a config error, so nothing here validates it beyond "non-empty".
public struct ActionNode: Equatable, Sendable {
    public var id: String
    public var title: String
    public var icon: Icon?
    public var action: String
    public var params: JSONValue

    public init(id: String, title: String, icon: Icon? = nil, action: String, params: JSONValue = .object([:])) {
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
        self.params = params
    }
}

/// A group with its own child ring. Groups nest to any depth.
public struct GroupNode: Equatable, Sendable {
    public var id: String
    public var title: String
    public var icon: Icon?
    public var children: [Node]
    /// Id of a node generator that fills this group from a runtime list (see `ConfigResolver`). Optional; a group
    /// without it works exactly as before.
    public var generate: String?
    /// Settings for the generator (e.g. `quality`). Ignored by groups that do not generate.
    public var params: JSONValue

    public init(id: String, title: String, icon: Icon? = nil, children: [Node], generate: String? = nil, params: JSONValue = .object([:])) {
        self.id = id
        self.title = title
        self.icon = icon
        self.children = children
        self.generate = generate
        self.params = params
    }
}

public enum Node: Equatable, Sendable, Codable {
    case action(ActionNode)
    case group(GroupNode)

    public var id: String {
        switch self {
        case .action(let node): node.id
        case .group(let node): node.id
        }
    }

    public var title: String {
        switch self {
        case .action(let node): node.title
        case .group(let node): node.title
        }
    }

    public var icon: Icon? {
        switch self {
        case .action(let node): node.icon
        case .group(let node): node.icon
        }
    }

    public var isGroup: Bool {
        if case .group = self { return true }
        return false
    }

    public var children: [Node]? {
        if case .group(let group) = self { return group.children }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, title, icon, action, params, children, generate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "action":
            self = .action(ActionNode(
                id: try container.decode(String.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title),
                icon: try container.decodeIfPresent(Icon.self, forKey: .icon),
                action: try container.decode(String.self, forKey: .action),
                params: try container.decodeIfPresent(JSONValue.self, forKey: .params) ?? .object([:])
            ))
        case "group":
            let generate = try container.decodeIfPresent(String.self, forKey: .generate)
            // A group that generates its children may leave "children" out; any other group still needs them.
            let children = generate != nil
                ? try container.decodeIfPresent([Node].self, forKey: .children) ?? []
                : try container.decode([Node].self, forKey: .children)
            self = .group(GroupNode(
                id: try container.decode(String.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title),
                icon: try container.decodeIfPresent(Icon.self, forKey: .icon),
                children: children,
                generate: generate,
                params: try container.decodeIfPresent(JSONValue.self, forKey: .params) ?? .object([:])
            ))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath + [CodingKeys.type],
                debugDescription: "unknown node type \"\(type)\" (expected \"action\" or \"group\")"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let node):
            try container.encode("action", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.title, forKey: .title)
            try container.encodeIfPresent(node.icon, forKey: .icon)
            try container.encode(node.action, forKey: .action)
            try container.encode(node.params, forKey: .params)
        case .group(let node):
            try container.encode("group", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.title, forKey: .title)
            try container.encodeIfPresent(node.icon, forKey: .icon)
            if node.generate == nil || !node.children.isEmpty { try container.encode(node.children, forKey: .children) }
            try container.encodeIfPresent(node.generate, forKey: .generate)
            if node.params != .object([:]) { try container.encode(node.params, forKey: .params) }
        }
    }
}
