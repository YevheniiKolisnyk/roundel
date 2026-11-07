import Foundation

/// Opens a file or folder with its default app (folders open in Finder).
public struct PathOpenAction: Action {
    public let id = "path.open"
    public let title = "Open File or Folder"
    public let defaultIcon: Icon = .symbol("folder")
    public var paramRules: ParamRules { ParamRules(specs: [.string("path", required: true)]) }

    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening) {
        self.workspace = workspace
    }

    private static func expand(_ path: String) -> String {
        NSString(string: path.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
    }

    public func extraValidation(_ params: Params) -> [ParamIssue] {
        guard let path = params.string("path"), !Self.expand(path).hasPrefix("/") else { return [] }
        return [ParamIssue(message: "\"path\" must be absolute or start with ~", blocksRun: true)]
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let raw = context.params.string("path") else { throw ActionError.failed("missing path") }
        let path = Self.expand(raw)
        let url = URL(fileURLWithPath: path)
        guard await workspace.fileExists(at: url) else { throw ActionError.failed("path not found: \(path)") }
        try await workspace.open(url)
        return .done
    }
}
