import Foundation

/// Switches between light and dark appearance through System Events (AppleScript).
/// Needs the Automation permission for System Events; macOS asks on first use.
public struct AppearanceToggleAction: Action {
    public let id = "appearance.toggle"
    public let title = "Dark Mode"
    public let defaultIcon: Icon = .symbol("circle.lefthalf.filled")
    public var paramRules: ParamRules { ParamRules(specs: []) }
    public var permissions: Set<Permission> { [.automationSystemEvents] }

    static let permissionHelp = "macOS blocked Roundel from controlling System Events. Allow it in System Settings → Privacy & Security → Automation, then try again."

    private let appearance: any AppearanceReading
    private let process: any ProcessRunning

    public init(appearance: any AppearanceReading, process: any ProcessRunning) {
        self.appearance = appearance
        self.process = process
    }

    @MainActor
    public func isActive(params: Params) -> Bool? { appearance.isDark }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        let makeDark = await !appearance.isDark
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(makeDark)"

        let result: ProcessResult
        do {
            result = try await process.run(ProcessRequest(executable: "/usr/bin/osascript", arguments: ["-e", script]))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ActionError.failed("could not start osascript: \(error.localizedDescription)")
        }

        if result.exitStatus != 0, result.stderr.contains("-1743") || result.stderr.contains("Not authorized") {
            throw ActionError.failed(Self.permissionHelp)
        }
        return try ProcessResultMapper.map(result, label: "osascript")
    }
}
