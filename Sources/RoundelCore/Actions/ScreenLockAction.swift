import Foundation

/// Locks the screen. Uses the private `SACLockScreenImmediate` symbol (looked up at runtime, so a missing symbol is
/// not fatal). If that is unavailable it falls back to `pmset displaysleepnow`, which only locks when macOS is set to
/// require a password right after the display sleeps.
public struct ScreenLockAction: Action {
    public let id = "screen.lock"
    public let title = "Lock Screen"
    public let defaultIcon: Icon = .symbol("lock.fill")
    public var paramRules: ParamRules { ParamRules(specs: []) }

    private let locker: any ScreenLocking
    private let process: any ProcessRunning

    public init(locker: any ScreenLocking, process: any ProcessRunning) {
        self.locker = locker
        self.process = process
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        if await locker.lockImmediately() { return .done }

        let result: ProcessResult
        do {
            result = try await process.run(ProcessRequest(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"]))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ActionError.failed("could not lock the screen: \(error.localizedDescription)")
        }
        return try ProcessResultMapper.map(result, label: "pmset")
    }
}
