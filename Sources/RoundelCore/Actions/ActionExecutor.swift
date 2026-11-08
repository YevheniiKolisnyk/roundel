import Foundation

/// Runs an action node: lookup, param validation, permission check, run with a timeout, and user feedback.
/// Never throws and never crashes on bad config or a failing action; every failure ends in a toast and a log line.
@MainActor
public final class ActionExecutor {
    private let registry: ActionRegistry
    private let permissions: any PermissionChecking
    private let reporter: any ActionReporting

    public init(registry: ActionRegistry, permissions: any PermissionChecking, reporter: any ActionReporting) {
        self.registry = registry
        self.permissions = permissions
        self.reporter = reporter
    }

    /// Runs the node the ring committed, found by id. An id that is missing or is a group is reported to the user, not
    /// only logged: a selection that does nothing, silently, looks exactly like a bug.
    public func execute(nodeWithID id: String, in config: RoundelConfig, files: [URL] = []) async {
        switch config.node(withID: id) {
        case .action(let node)?:
            await execute(node, files: files)
        case .group(let group)?:
            reporter.warning("Selected '\(id)' but it is a group, not an action")
            reporter.toast("“\(group.title)” is a group, not an action", isError: true)
        case nil:
            reporter.warning("Selected '\(id)' but it is not in the current config")
            reporter.toast("“\(id)” is not in the current config", isError: true)
        }
    }

    /// - Parameter files: the files dropped on the node, if the ring was used for a file drag.
    public func execute(_ node: ActionNode, files: [URL] = []) async {
        guard let action = registry.action(for: node.action) else {
            reporter.warning("Node '\(node.id)' uses unknown action '\(node.action)'")
            reporter.toast("Unknown action “\(node.action)” (node “\(node.title)”)", isError: true)
            return
        }

        if !files.isEmpty, !action.acceptedInputs.contains(.files) {
            reporter.toast("\(action.title) doesn’t take files", isError: true)
            return
        }
        if files.isEmpty, action.acceptedInputs.contains(.files), !action.acceptedInputs.contains(.none) {
            reporter.toast("\(action.title) needs files: drag some from Finder onto it", isError: true)
            return
        }

        let params = Params(node.params)
        let issues = action.paramRules.validate(node.params, actionID: action.id) + action.extraValidation(params)
        for issue in issues {
            reporter.warning("Node '\(node.id)' (\(action.id)): \(issue.message)")
        }
        if let blocking = issues.first(where: \.blocksRun) {
            reporter.toast("\(action.title): \(blocking.message)", isError: true)
            return
        }

        for permission in action.permissions.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch permissions.status(of: permission) {
            case .granted, .notDetermined:
                continue   // notDetermined: running lets macOS show its own prompt
            case .denied:
                permissions.request(permission)
                reporter.warning("Action '\(action.id)' needs the \(permission.displayName) permission")
                reporter.toast("\(action.title) needs the \(permission.displayName) permission. Allow Roundel in System Settings → Privacy & Security, then try again.", isError: true)
                return
            }
        }

        reporter.info("Run action '\(action.id)' [node '\(node.id)', \"\(node.title)\"] params=\(Self.compact(node.params))")

        let relay = ProgressRelay(reporter: reporter)
        let context = ActionContext(nodeID: node.id, title: node.title, params: params, files: files, reportProgress: { relay.send($0) })
        let timeout = action.timeout(for: params, fileCount: files.count)
        do {
            let result = try await raceWithTimeout(timeout) { try await action.run(context) }
            switch result {
            case .done: break
            case .message(let text): reporter.toast(text, isError: false)
            case .warning(let text): reporter.toast(text, isError: true)
            }
        } catch is CancellationError {
            reporter.info("Action '\(action.id)' was cancelled")
        } catch let error as ActionTimeoutError {
            reporter.warning("Action '\(action.id)' [node '\(node.id)'] timed out after \(error.duration)")
            reporter.toast("\(action.title) timed out after \(Self.seconds(error.duration)) s", isError: true)
        } catch let error as ActionError {
            reporter.warning("Action '\(action.id)' [node '\(node.id)'] failed: \(error.message)")
            reporter.toast("\(action.title): \(error.message)", isError: true)
        } catch {
            reporter.warning("Action '\(action.id)' [node '\(node.id)'] failed: \(error)")
            reporter.toast("\(action.title): \(error.localizedDescription)", isError: true)
        }
    }

    /// Lets an action report progress from any thread; the reporter itself lives on the main actor.
    private struct ProgressRelay: @unchecked Sendable {
        let reporter: any ActionReporting
        func send(_ message: String) {
            let reporter = reporter
            Task { @MainActor in reporter.progress(message) }
        }
    }

    private static func seconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds)
    }

    private static func compact(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
    }
}
