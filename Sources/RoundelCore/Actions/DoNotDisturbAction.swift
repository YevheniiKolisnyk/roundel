import Foundation

/// Do Not Disturb has no public API, so this runs a Shortcut of the user's own (one that uses the "Set Focus" action).
/// There is also no public way to read the Focus state, so it shows no active indicator.
public struct DoNotDisturbAction: Action {
    public let id = "dnd.toggle"
    public let title = "Do Not Disturb"
    public let defaultIcon: Icon = .symbol("moon.fill")
    public static let defaultShortcutName = "Toggle Do Not Disturb"
    public static let defaultTimeoutSeconds = 30

    public var paramRules: ParamRules {
        ParamRules(specs: [.string("shortcut"), .int("timeoutSec", range: 1...120)])
    }

    private let runner: ShortcutRunner

    public init(process: any ProcessRunning) {
        runner = ShortcutRunner(process: process)
    }

    public func timeout(for params: Params) -> Duration {
        .seconds(params.int("timeoutSec") ?? Self.defaultTimeoutSeconds)
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        try await runner.run(named: context.params.string("shortcut") ?? Self.defaultShortcutName)
    }
}
