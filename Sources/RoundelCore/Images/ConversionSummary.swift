import Foundation

/// Something worth telling the user about a conversion that otherwise worked.
public enum ConversionNote: Equatable, Sendable {
    /// The source was animated; only its first frame was converted.
    case firstFrameOnly
}

public enum SkipReason: Equatable, Sendable {
    case alreadyInFormat
}

public enum ConversionItemResult: Equatable, Sendable {
    case converted(source: URL, output: URL, note: ConversionNote?)
    case skipped(source: URL, reason: SkipReason)
    case failed(source: URL, message: String)
}

/// The outcome of a whole batch and the one toast that tells the user about it.
public struct ConversionSummary: Equatable, Sendable {
    public let results: [ConversionItemResult]
    public let format: ImageFormat

    public init(results: [ConversionItemResult], format: ImageFormat) {
        self.results = results
        self.format = format
    }

    public var convertedCount: Int { results.filter { if case .converted = $0 { true } else { false } }.count }
    public var skippedCount: Int { results.filter { if case .skipped = $0 { true } else { false } }.count }
    public var failedCount: Int { results.filter { if case .failed = $0 { true } else { false } }.count }

    /// Something failed but something else worked.
    public var isWarning: Bool { failedCount > 0 && convertedCount > 0 }
    /// Nothing was converted and at least one file failed.
    public var isTotalFailure: Bool { failedCount > 0 && convertedCount == 0 }

    public static func progressMessage(done: Int, total: Int) -> String { "Converting \(done)/\(total)" }

    // MARK: Text

    public var message: String {
        if results.isEmpty { return "No files to convert" }
        if convertedCount == 0 && failedCount == 0 { return "Nothing to convert: already \(format.displayName)" }

        var parts: [String] = []
        if results.count == 1, case .converted(let source, let output, _)? = results.first {
            parts.append("Converted \(source.lastPathComponent) → \(output.lastPathComponent)")
        } else if failedCount > 0 {
            parts.append("Converted \(convertedCount) of \(convertedCount + failedCount) files to \(format.displayName)")
        } else {
            parts.append("Converted \(convertedCount) \(convertedCount == 1 ? "file" : "files") to \(format.displayName)")
        }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped (already \(format.displayName))") }
        if failedCount > 0 { parts.append("\(failedCount) failed: \(failureList)") }
        if let note = animatedNote { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    /// What to tell the user when nothing could be converted.
    public var failureText: String {
        let failures = failedItems
        if failures.count == 1, let only = failures.first { return "Couldn’t convert \(only.name) (\(only.message))" }
        return "Couldn’t convert \(failures.count) files: \(failureList)"
    }

    // MARK: Private

    private var failedItems: [(name: String, message: String)] {
        results.compactMap { if case .failed(let source, let message) = $0 { (source.lastPathComponent, message) } else { nil } }
    }

    private var failureList: String {
        let failures = failedItems
        let shown = failures.prefix(3).map { "\($0.name) (\($0.message))" }.joined(separator: ", ")
        return failures.count > 3 ? "\(shown) and \(failures.count - 3) more" : shown
    }

    private var animatedNote: String? {
        let animated = results.compactMap { result -> String? in
            if case .converted(let source, _, .firstFrameOnly?) = result { return source.lastPathComponent }
            return nil
        }
        switch animated.count {
        case 0: return nil
        case 1: return "\(animated[0]) is animated: only the first frame was converted"
        default: return "\(animated.count) animated files: only the first frame was converted"
        }
    }
}
