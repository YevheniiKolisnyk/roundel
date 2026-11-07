import Foundation

public struct ActionWarning: Hashable, Sendable, CustomStringConvertible {
    public let nodeID: String
    public let message: String

    public init(nodeID: String, message: String) {
        self.nodeID = nodeID
        self.message = message
    }

    public var description: String { "node '\(nodeID)': \(message)" }
}

/// Remembers the last set of warnings so a toast is shown only when that set changes, not on every hot reload.
public struct WarningTracker: Sendable {
    private var last: Set<ActionWarning> = []

    public init() {}

    /// Returns true when there are warnings and they differ from the previous set.
    public mutating func update(_ warnings: [ActionWarning]) -> Bool {
        let current = Set(warnings)
        defer { last = current }
        return !current.isEmpty && current != last
    }
}

public struct ActionRegistry: Sendable {
    private var byID: [String: any Action] = [:]
    public private(set) var ids: [String] = []
    public private(set) var duplicateIDs: [String] = []

    public init(_ actions: [any Action]) {
        for action in actions {
            if byID[action.id] != nil {
                duplicateIDs.append(action.id)
            } else {
                byID[action.id] = action
                ids.append(action.id)
            }
        }
    }

    public func action(for id: String) -> (any Action)? { byID[id] }

    /// False for an unknown action id: the node is shown dimmed. Never a config error.
    public func isAvailable(_ node: ActionNode) -> Bool { byID[node.action] != nil }

    public func defaultIcon(for node: ActionNode) -> Icon? { byID[node.action]?.defaultIcon }

    @MainActor
    public func isActive(_ node: ActionNode) -> Bool? {
        byID[node.action]?.isActive(params: Params(node.params))
    }

    /// Everything wrong with action nodes in a config: unknown ids and bad params. Warnings, never failures.
    public func warnings(for config: RoundelConfig) -> [ActionWarning] {
        var result: [ActionWarning] = []
        func visit(_ nodes: [Node]) {
            for node in nodes {
                switch node {
                case .group(let group):
                    visit(group.children)
                case .action(let action):
                    guard let known = byID[action.action] else {
                        result.append(ActionWarning(nodeID: action.id, message: "unknown action '\(action.action)' (the node is shown dimmed)"))
                        continue
                    }
                    let issues = known.paramRules.validate(action.params, actionID: known.id) + known.extraValidation(Params(action.params))
                    for issue in issues {
                        result.append(ActionWarning(nodeID: action.id, message: "action '\(known.id)': \(issue.message)"))
                    }
                }
            }
        }
        visit(config.ring)
        return result
    }

    /// The shipped actions. Adding an action = its file + one line here.
    public static func standard(services s: ActionServices) -> ActionRegistry {
        ActionRegistry([
            LogAction(logger: s.logger),
            AppOpenAction(workspace: s.workspace),
            URLOpenAction(workspace: s.workspace),
            PathOpenAction(workspace: s.workspace),
            ShellRunAction(process: s.process),
            ShortcutRunAction(process: s.process),
            CaffeinateAction(power: s.power),
            ScreenLockAction(locker: s.screenLocker, process: s.process),
            AppearanceToggleAction(appearance: s.appearance, process: s.process),
            DoNotDisturbAction(process: s.process),
            MediaPlayPauseAction(media: s.media),
            MediaNextAction(media: s.media),
            MediaPreviousAction(media: s.media),
            MuteToggleAction(mute: s.mute),
        ])
    }
}
