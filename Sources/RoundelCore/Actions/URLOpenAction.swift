import Foundation

/// Opens a URL (http, https, mailto, or any custom scheme) with its default handler.
public struct URLOpenAction: Action {
    public let id = "url.open"
    public let title = "Open URL"
    public let defaultIcon: Icon = .symbol("link")
    public var paramRules: ParamRules { ParamRules(specs: [.string("url", required: true)]) }

    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening) {
        self.workspace = workspace
    }

    private static let schemeProblem = "\"url\" must be a full URL with a scheme, e.g. https://example.com"

    private static func parse(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    public func extraValidation(_ params: Params) -> [ParamIssue] {
        guard let text = params.string("url"), Self.parse(text) == nil else { return [] }
        return [ParamIssue(message: Self.schemeProblem, blocksRun: true)]
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let text = context.params.string("url"), let url = Self.parse(text) else {
            throw ActionError.failed(Self.schemeProblem)
        }
        try await workspace.open(url)
        return .done
    }
}
