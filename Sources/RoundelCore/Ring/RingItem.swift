import Foundation

/// What the view draws for one section. Built from nodes; later the action registry decides availability.
public struct RingItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let icon: Icon?
    public let isGroup: Bool
    /// Action whose id the registry does not know: drawn dimmed, logged as a warning when chosen. Never a config error.
    public let isDimmed: Bool

    public init(id: String, title: String, icon: Icon?, isGroup: Bool, isDimmed: Bool) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isGroup = isGroup
        self.isDimmed = isDimmed
    }

    public static func items(for nodes: [Node], isAvailable: (ActionNode) -> Bool = { _ in true }) -> [RingItem] {
        nodes.map { node in
            switch node {
            case .action(let action):
                RingItem(id: action.id, title: action.title, icon: action.icon, isGroup: false, isDimmed: !isAvailable(action))
            case .group(let group):
                RingItem(id: group.id, title: group.title, icon: group.icon, isGroup: true, isDimmed: false)
            }
        }
    }

    /// Shown when a node has no icon.
    public static func fallbackLetter(for title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "•" }
        return String(first).uppercased()
    }
}
