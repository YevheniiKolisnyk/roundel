import Foundation

/// What the view draws for one section. Built from nodes plus what the action registry knows about them.
public struct RingItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let icon: Icon?
    public let isGroup: Bool
    /// Action whose id the registry does not know: drawn dimmed, warns when chosen. Never a config error.
    public let isDimmed: Bool
    /// On/off state of a toggle action (caffeinate, dark mode, mute); `nil` when the action has no state.
    public let isActive: Bool?

    public init(id: String, title: String, icon: Icon?, isGroup: Bool, isDimmed: Bool, isActive: Bool? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isGroup = isGroup
        self.isDimmed = isDimmed
        self.isActive = isActive
    }

    /// - Parameters:
    ///   - isAvailable: whether the action id is registered.
    ///   - isActive: the toggle state of the action, if it has one.
    ///   - defaultIcon: the action's own icon, used when the node does not set one.
    public static func items(
        for nodes: [Node],
        isAvailable: (ActionNode) -> Bool = { _ in true },
        isActive: (ActionNode) -> Bool? = { _ in nil },
        defaultIcon: (ActionNode) -> Icon? = { _ in nil }
    ) -> [RingItem] {
        nodes.map { node in
            switch node {
            case .action(let action):
                RingItem(id: action.id, title: action.title, icon: action.icon ?? defaultIcon(action), isGroup: false,
                         isDimmed: !isAvailable(action), isActive: isActive(action))
            case .group(let group):
                RingItem(id: group.id, title: group.title, icon: group.icon, isGroup: true, isDimmed: false)
            }
        }
    }

    /// Shown when a node has no icon and its action offers none either.
    public static func fallbackLetter(for title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "•" }
        return String(first).uppercased()
    }
}
