import Foundation

/// Toggles a power assertion that keeps the Mac (or just the display) awake. Optional auto-off after `minutes`.
/// Like the `caffeinate` tool, it does not stop sleep caused by closing the lid.
public struct CaffeinateAction: Action {
    public let id = "caffeinate.toggle"
    public let title = "Caffeinate"
    public let defaultIcon: Icon = .symbol("cup.and.saucer.fill")

    public var paramRules: ParamRules {
        ParamRules(specs: [.string("mode", allowed: ["display", "system"]), .int("minutes", range: 1...1440)])
    }

    private let power: any PowerAssertionHolding

    public init(power: any PowerAssertionHolding) {
        self.power = power
    }

    @MainActor
    public func isActive(params: Params) -> Bool? { power.isHeld }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        if await power.isHeld {
            await power.release()
            return .message("Caffeinate off")
        }

        let mode = SleepPreventionMode(rawValue: context.params.string("mode") ?? "") ?? .display
        let minutes = context.params.int("minutes")
        try await power.acquire(mode: mode, reason: "Roundel: caffeinate", releaseAfter: minutes.map { TimeInterval($0 * 60) })

        let duration = minutes.map { " for \($0) min" } ?? ""
        let scope = mode == .display ? "keeps the display awake" : "keeps the Mac awake"
        return .message("Caffeinate on\(duration) (\(scope))")
    }
}
