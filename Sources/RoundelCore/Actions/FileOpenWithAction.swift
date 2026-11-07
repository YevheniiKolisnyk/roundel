import Foundation

/// Opens the dropped files with a given application, by name or bundle id.
public struct FileOpenWithAction: Action {
    public let id = "file.openWith"
    public let title = "Open With"
    public let defaultIcon: Icon = .symbol("arrow.up.forward.app")
    public var acceptedInputs: Set<ActionInput> { [.files] }
    public var paramRules: ParamRules {
        ParamRules(specs: [.string("name"), .string("bundleId")], exactlyOneOf: [["name", "bundleId"]])
    }

    private let workspace: any WorkspaceOpening
    private let resolver: AppNameResolver

    public init(workspace: any WorkspaceOpening, resolver: AppNameResolver = AppNameResolver()) {
        self.workspace = workspace
        self.resolver = resolver
    }

    public func extraValidation(_ params: Params) -> [ParamIssue] { AppLookup.validate(params) }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard !context.files.isEmpty else { throw ActionError.failed("no files to open") }
        let app = try await AppLookup.applicationURL(for: context.params, workspace: workspace, resolver: resolver)
        try await workspace.open(context.files, withApplicationAt: app)
        return .done
    }
}
