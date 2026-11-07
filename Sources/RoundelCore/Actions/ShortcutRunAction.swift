import Foundation

/// Runs an Apple Shortcut by name.
public struct ShortcutRunAction: Action {
    public let id = "shortcut.run"
    public let title = "Run Shortcut"
    public let defaultIcon: Icon = .symbol("bolt.fill")
    public static let defaultTimeoutSeconds = 60

    public var paramRules: ParamRules {
        ParamRules(specs: [.string("name", required: true), .int("timeoutSec", range: 1...600)])
    }

    private let runner: ShortcutRunner

    public init(process: any ProcessRunning) {
        runner = ShortcutRunner(process: process)
    }

    public func timeout(for params: Params) -> Duration {
        .seconds(params.int("timeoutSec") ?? Self.defaultTimeoutSeconds)
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let name = context.params.string("name") else { throw ActionError.failed("missing Shortcut name") }
        return try await runner.run(named: name)
    }
}
