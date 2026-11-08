import Foundation

public enum CompressionItemResult: Equatable, Sendable {
    case compressed(source: URL, output: URL, bytesBefore: Int, bytesAfter: Int)
    /// Compressing would not have saved enough (or the file is already compressed as far as is sensible); nothing was written.
    case alreadyOptimal(source: URL)
    case skipped(source: URL, reason: CompressionSkipReason)
    case failed(source: URL, message: String)
}

/// The outcome of a whole batch and the one toast that tells the user about it.
public struct CompressionSummary: Equatable, Sendable {
    public let results: [CompressionItemResult]

    public init(results: [CompressionItemResult]) {
        self.results = results
    }

    public var compressedCount: Int { results.filter { if case .compressed = $0 { true } else { false } }.count }
    public var alreadyOptimalCount: Int { results.filter { if case .alreadyOptimal = $0 { true } else { false } }.count }
    public var skippedCount: Int { results.filter { if case .skipped = $0 { true } else { false } }.count }
    public var failedCount: Int { results.filter { if case .failed = $0 { true } else { false } }.count }

    /// Sizes of the files that were compressed, before and after.
    public var bytesBefore: Int { results.reduce(0) { if case .compressed(_, _, let before, _) = $1 { $0 + before } else { $0 } } }
    public var bytesAfter: Int { results.reduce(0) { if case .compressed(_, _, _, let after) = $1 { $0 + after } else { $0 } } }
    public var savedPercent: Int { ByteSize.savedPercent(before: bytesBefore, after: bytesAfter) }

    /// Something failed but something else worked.
    public var isWarning: Bool { failedCount > 0 && compressedCount > 0 }
    /// Something failed and nothing was compressed.
    public var isTotalFailure: Bool { failedCount > 0 && compressedCount == 0 }

    public static func progressMessage(done: Int, total: Int) -> String { "Compressing \(done)/\(total)" }

    // MARK: Text

    public var message: String {
        if results.isEmpty { return "No files to compress" }

        var parts: [String] = []
        if compressedCount == 0 {
            if failedCount == 0 {
                if skippedCount == 0 {
                    if results.count == 1, case .alreadyOptimal(let source)? = results.first { return "\(source.lastPathComponent) is already optimal" }
                    return "Nothing to compress: \(alreadyOptimalCount) files already optimal"
                }
                parts.append(alreadyOptimalCount > 0 ? "Nothing to compress: \(alreadyOptimalCount) already optimal" : "Nothing to compress")
            }
        } else {
            let saved = "saved \(savedPercent)% (\(ByteSize.format(bytesBefore)) → \(ByteSize.format(bytesAfter)))"
            if results.count == 1, case .compressed(let source, let output, _, _)? = results.first {
                parts.append("Compressed \(source.lastPathComponent) → \(output.lastPathComponent), \(saved)")
            } else if failedCount > 0 || skippedCount > 0 || alreadyOptimalCount > 0 {
                let considered = compressedCount + failedCount + (failedCount > 0 ? 0 : 0)
                let noun = compressedCount == 1 && considered == 1 ? "file" : "files"
                parts.append(failedCount > 0 ? "Compressed \(compressedCount) of \(considered) \(noun), \(saved)" : "Compressed \(compressedCount) \(compressedCount == 1 ? "file" : "files"), \(saved)")
            } else {
                parts.append("Compressed \(compressedCount) files, \(saved)")
            }
            if alreadyOptimalCount > 0 { parts.append("\(alreadyOptimalCount) already optimal") }
        }
        if compressedCount == 0, failedCount > 0, alreadyOptimalCount > 0 { parts.append("\(alreadyOptimalCount) already optimal") }
        if let skipped = skippedText { parts.append(skipped) }
        if failedCount > 0 { parts.append("\(failedCount) failed: \(failureList)") }
        return parts.joined(separator: " · ")
    }

    /// What to tell the user when nothing could be compressed because of failures.
    public var failureText: String {
        let failures = failedItems
        if failures.count == 1, let only = failures.first { return "Couldn’t compress \(only.name) (\(only.message))" }
        return "Couldn’t compress \(failures.count) files: \(failureList)"
    }

    // MARK: Private

    private var failedItems: [(name: String, message: String)] {
        results.compactMap { result in
            guard case .failed(let source, let message) = result else { return nil }
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return (source.lastPathComponent, text.isEmpty ? "unknown error" : text)
        }
    }

    private var failureList: String {
        let failures = failedItems
        let shown = failures.prefix(3).map { "\($0.name) (\($0.message))" }.joined(separator: ", ")
        return failures.count > 3 ? "\(shown) and \(failures.count - 3) more" : shown
    }

    /// "a.gif: GIF isn’t compressed; use Convert to WebP · b.gif: ..." for up to three files, then a count.
    private var skippedText: String? {
        let skipped = results.compactMap { result -> String? in
            guard case .skipped(let source, let reason) = result else { return nil }
            return "\(source.lastPathComponent): \(reason.message)"
        }
        guard !skipped.isEmpty else { return nil }
        let shown = skipped.prefix(3).joined(separator: " · ")
        return skipped.count > 3 ? "\(shown) · and \(skipped.count - 3) more skipped" : shown
    }
}
