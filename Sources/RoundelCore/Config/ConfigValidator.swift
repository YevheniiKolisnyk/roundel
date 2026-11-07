import Foundation

/// Rules that need the whole file: non-empty rings, non-blank ids/titles, globally unique ids.
enum ConfigValidator {
    static func validate(_ config: RoundelConfig) -> [ConfigIssue] {
        var issues: [ConfigIssue] = []
        var firstUse: [String: String] = [:]

        if config.ring.isEmpty {
            issues.append(ConfigIssue(path: "ring", message: "ring must contain at least one node"))
        }
        walk(config.ring, prefix: "ring", issues: &issues, firstUse: &firstUse)
        return issues
    }

    private static func walk(_ nodes: [Node], prefix: String, issues: inout [ConfigIssue], firstUse: inout [String: String]) {
        for (index, node) in nodes.enumerated() {
            let path = "\(prefix)[\(index)]"

            if node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ConfigIssue(path: "\(path).id", message: "id must not be empty"))
            } else if let first = firstUse[node.id] {
                issues.append(ConfigIssue(path: "\(path).id", message: "duplicate id \"\(node.id)\" (first used at \(first))"))
            } else {
                firstUse[node.id] = "\(path).id"
            }

            if node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ConfigIssue(path: "\(path).title", message: "title must not be empty"))
            }

            switch node {
            case .action(let action):
                if action.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(ConfigIssue(path: "\(path).action", message: "action must not be empty"))
                }
            case .group(let group):
                if group.children.isEmpty && group.generate == nil {
                    issues.append(ConfigIssue(path: "\(path).children", message: "a group needs at least one child"))
                }
                walk(group.children, prefix: "\(path).children", issues: &issues, firstUse: &firstUse)
            }
        }
    }
}
