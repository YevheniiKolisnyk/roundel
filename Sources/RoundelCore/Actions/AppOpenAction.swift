import Foundation

/// Folders searched, in order, when an app is opened by name.
public struct AppNameResolver: Sendable {
    public let searchDirectories: [String]

    public init(home: String = NSHomeDirectory()) {
        searchDirectories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            home + "/Applications",
        ]
    }

    /// "  Foo.app " -> "Foo"
    public static func normalize(_ name: String) -> String {
        var cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasSuffix(".app") { cleaned.removeLast(4) }
        return cleaned
    }

    public func candidates(for name: String) -> [URL] {
        let bundle = Self.normalize(name) + ".app"
        return searchDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent(bundle) }
    }
}

/// Opens an application by name (file name in the standard Applications folders) or by bundle id.
public struct AppOpenAction: Action {
    public let id = "app.open"
    public let title = "Open App"
    public let defaultIcon: Icon = .symbol("square.grid.2x2")
    public var paramRules: ParamRules {
        ParamRules(specs: [.string("name"), .string("bundleId")], exactlyOneOf: [["name", "bundleId"]])
    }

    private let workspace: any WorkspaceOpening
    private let resolver: AppNameResolver

    public init(workspace: any WorkspaceOpening, resolver: AppNameResolver = AppNameResolver()) {
        self.workspace = workspace
        self.resolver = resolver
    }

    public func extraValidation(_ params: Params) -> [ParamIssue] {
        if let name = params.string("name"), name.contains("/") {
            return [ParamIssue(message: "\"name\" must be an application name, not a path (use \"bundleId\" for exactness)", blocksRun: true)]
        }
        return []
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        if let bundleID = context.params.string("bundleId") {
            guard let url = await workspace.applicationURL(forBundleID: bundleID) else {
                throw ActionError.failed("no application with bundle id “\(bundleID)”")
            }
            try await workspace.openApplication(at: url)
            return .done
        }

        guard let name = context.params.string("name") else { throw ActionError.failed("missing app name") }
        for url in resolver.candidates(for: name) where await workspace.fileExists(at: url) {
            try await workspace.openApplication(at: url)
            return .done
        }
        throw ActionError.failed("application “\(name)” not found")
    }
}
