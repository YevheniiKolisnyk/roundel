/// Writes a line to the log. Handy for trying out a ring layout.
public struct LogAction: Action {
    public let id = "log"
    public let title = "Log Message"
    public let defaultIcon: Icon = .symbol("text.alignleft")
    public var paramRules: ParamRules { ParamRules(specs: [.string("message")]) }

    private let logger: any ActionLogging

    public init(logger: any ActionLogging) {
        self.logger = logger
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        logger.info("log [\(context.nodeID)]: \(context.params.string("message") ?? context.title)")
        return .done
    }
}
