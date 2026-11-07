import Foundation

/// Turns a finished child process into success or a short user-facing error. Shared by every process-backed action.
public enum ProcessResultMapper {
    public static let maxMessageLength = 240

    public static func map(_ result: ProcessResult, label: String) throws -> ActionResult {
        if result.terminatedBySignal {
            throw ActionError.failed("\(label) was terminated by signal \(result.exitStatus)")
        }
        if result.exitStatus == 0 { return .done }

        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if stderr.isEmpty {
            throw ActionError.failed("\(label) exited with status \(result.exitStatus)")
        }
        throw ActionError.failed(tail(of: stderr))
    }

    /// The end of stderr is where errors usually are, so a long message keeps its tail.
    static func tail(of text: String) -> String {
        guard text.count > maxMessageLength else { return text }
        return "…" + String(text.suffix(maxMessageLength))
    }
}
