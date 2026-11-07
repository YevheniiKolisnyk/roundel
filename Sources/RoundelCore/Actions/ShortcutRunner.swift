import Foundation

/// Runs a Shortcut by name with the `shortcuts` command-line tool (no Shortcuts window pops up).
struct ShortcutRunner: Sendable {
    let process: any ProcessRunning

    func run(named name: String) async throws -> ActionResult {
        let result: ProcessResult
        do {
            result = try await process.run(ProcessRequest(executable: "/usr/bin/shortcuts", arguments: ["run", name]))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ActionError.failed("could not start /usr/bin/shortcuts: \(error.localizedDescription)")
        }
        let label = "Shortcut “\(name)”"
        do {
            return try ProcessResultMapper.map(result, label: label)
        } catch let error as ActionError {
            // The CLI's own message is localized and never names the shortcut, so say which one failed.
            let hasStderr = !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasStderr, !result.terminatedBySignal { throw ActionError.failed("\(label): \(error.message)") }
            throw error
        }
    }
}
