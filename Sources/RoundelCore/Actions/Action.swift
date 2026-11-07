import Foundation

/// What an action can take as input. M3 actions need none; files and text arrive with later milestones.
public enum ActionInput: Sendable {
    case none, files, text
}

public enum Permission: String, CaseIterable, Hashable, Sendable {
    case accessibility
    case automationSystemEvents

    public var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .automationSystemEvents: "Automation (System Events)"
        }
    }
}

public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    /// macOS has not asked yet; running the action lets the system show its prompt.
    case notDetermined
}

public enum ActionResult: Equatable, Sendable {
    case done
    /// Short feedback shown as a toast, e.g. "Caffeinate on".
    case message(String)
    /// Like `message`, but something went partly wrong: shown in the error style.
    case warning(String)
}

/// A failure with a message that is safe to show to the user as is.
public struct ActionError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public static func failed(_ message: String) -> ActionError { ActionError(message) }
}

public struct ActionContext: Sendable {
    public let nodeID: String
    public let title: String
    public let params: Params
    /// Files dropped on the node (empty when the action was not triggered by a file drag).
    public let files: [URL]
    /// Tells the user how a long run is going (e.g. "Converting 4/10"). Safe to call from any thread.
    public let reportProgress: @Sendable (String) -> Void

    public init(nodeID: String, title: String, params: Params, files: [URL] = [],
                reportProgress: @escaping @Sendable (String) -> Void = { _ in }) {
        self.nodeID = nodeID
        self.title = title
        self.params = params
        self.files = files
        self.reportProgress = reportProgress
    }
}

/// One thing the ring can do. Adding an action = one file conforming to this + one line in `ActionRegistry.standard`.
public protocol Action: Sendable {
    /// Stable id used in config.json, e.g. "app.open".
    var id: String { get }
    var title: String { get }
    /// Shown for nodes that have no icon of their own.
    var defaultIcon: Icon { get }
    var acceptedInputs: Set<ActionInput> { get }
    var paramRules: ParamRules { get }
    var permissions: Set<Permission> { get }

    /// Upper bound for `run`. When it passes, the run is cancelled and the user sees a timeout toast.
    func timeout(for params: Params) -> Duration
    /// Same, when the number of dropped files matters. Defaults to `timeout(for:)`.
    func timeout(for params: Params, fileCount: Int) -> Duration
    /// Checks the rules that `ParamRules` cannot express. Issues with `blocksRun` stop the run.
    func extraValidation(_ params: Params) -> [ParamIssue]
    /// Must honor cancellation (stop work, kill child processes). Failures are thrown as `ActionError`.
    func run(_ context: ActionContext) async throws -> ActionResult
    /// On/off state for the ring's active indicator, or `nil` for actions that have none.
    /// Called while the ring is built, so it must be a cheap, synchronous read.
    @MainActor func isActive(params: Params) -> Bool?
}

public extension Action {
    var acceptedInputs: Set<ActionInput> { [.none] }
    var permissions: Set<Permission> { [] }
    func timeout(for params: Params) -> Duration { .seconds(15) }
    func timeout(for params: Params, fileCount: Int) -> Duration { timeout(for: params) }
    func extraValidation(_ params: Params) -> [ParamIssue] { [] }
    @MainActor func isActive(params: Params) -> Bool? { nil }
}

public extension Action {
    /// Whether the ring offers this action as usable. During a file drag only actions that take files are; otherwise
    /// every action is except those that need files. (Selected-text actions need neither: they are usable without a drag.)
    func isUsable(duringFileDrag: Bool) -> Bool {
        let takesFiles = acceptedInputs.contains(.files)
        if duringFileDrag { return takesFiles }
        return !(takesFiles && !acceptedInputs.contains(.none))
    }
}
