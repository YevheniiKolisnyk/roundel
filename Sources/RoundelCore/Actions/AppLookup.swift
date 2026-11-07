import Foundation

/// Finds an application from the `name` / `bundleId` params shared by `app.open` and `file.openWith`.
enum AppLookup {
    static func validate(_ params: Params) -> [ParamIssue] {
        if let name = params.string("name"), name.contains("/") {
            return [ParamIssue(message: "\"name\" must be an application name, not a path (use \"bundleId\" for exactness)", blocksRun: true)]
        }
        return []
    }

    @MainActor
    static func applicationURL(for params: Params, workspace: any WorkspaceOpening, resolver: AppNameResolver) async throws -> URL {
        if let bundleID = params.string("bundleId") {
            guard let url = workspace.applicationURL(forBundleID: bundleID) else {
                throw ActionError.failed("no application with bundle id “\(bundleID)”")
            }
            return url
        }
        guard let name = params.string("name") else { throw ActionError.failed("missing app name") }
        for url in resolver.candidates(for: name) where workspace.fileExists(at: url) { return url }
        throw ActionError.failed("application “\(name)” not found")
    }
}
