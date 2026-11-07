import Foundation

/// Runs `/bin/zsh -c <script> zsh <args…>` off the main thread with a timeout. A non-zero exit shows stderr.
/// GUI apps start with a minimal PATH; set `login: true` to run `zsh -lc` so ~/.zprofile (Homebrew etc.) is loaded.
public struct ShellRunAction: Action {
    public let id = "shell.run"
    public let title = "Run Shell Script"
    public let defaultIcon: Icon = .symbol("terminal")
    public static let defaultTimeoutSeconds = 30

    public var paramRules: ParamRules {
        ParamRules(specs: [
            .string("script", required: true),
            .stringList("args"),
            .string("cwd"),
            .int("timeoutSec", range: 1...600),
            .bool("login"),
        ])
    }

    private let process: any ProcessRunning

    public init(process: any ProcessRunning) {
        self.process = process
    }

    public func timeout(for params: Params) -> Duration {
        .seconds(params.int("timeoutSec") ?? Self.defaultTimeoutSeconds)
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let script = context.params.string("script") else { throw ActionError.failed("missing script") }

        let flag = context.params.bool("login") == true ? "-lc" : "-c"
        let arguments = [flag, script, "zsh"] + (context.params.stringList("args") ?? [])
        let cwd = context.params.string("cwd").map { NSString(string: $0).expandingTildeInPath }

        let result: ProcessResult
        do {
            result = try await process.run(ProcessRequest(executable: "/bin/zsh", arguments: arguments, workingDirectory: cwd))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ActionError.failed("could not start /bin/zsh: \(error.localizedDescription)")
        }
        return try ProcessResultMapper.map(result, label: "Script")
    }
}
