import Foundation

/// Makes the dropped images smaller, next to the originals. See `ImageCompressor` for the rules.
public struct ImageCompressAction: Action {
    public let id = "image.compress"
    public let title = "Compress Image"
    public let defaultIcon: Icon = .symbol("arrow.down.right.and.arrow.up.left")
    public var acceptedInputs: Set<ActionInput> { [.files] }
    public var paramRules: ParamRules {
        ParamRules(specs: [.string("preset", allowed: CompressionPreset.allCases.map(\.rawValue)), .number("quality", range: 0...1),
                           .int("maxDimension", range: 16...100_000), .bool("stripMetadata")])
    }

    private let compressor: any ImageCompressing

    public init(compressor: any ImageCompressing) {
        self.compressor = compressor
    }

    /// Half a minute of headroom, plus half a minute per file (big photos and thorough PNG recompression take a while), at most an hour.
    public func timeout(for params: Params, fileCount: Int) -> Duration {
        .seconds(min(3600, 30 + 30 * max(fileCount, 1)))
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard !context.files.isEmpty else { throw ActionError.failed("no files to compress") }

        let report = context.reportProgress
        let showsProgress = context.files.count > 1
        let results = await compressor.compress(files: context.files, options: CompressionOptions(params: context.params)) { done, total in
            if showsProgress { report(CompressionSummary.progressMessage(done: done, total: total)) }
        }

        // Every dropped file must come back as compressed, already optimal, skipped or failed.
        guard results.count == context.files.count else {
            throw ActionError.failed("the compressor reported on \(results.count) of \(context.files.count) files")
        }
        let summary = CompressionSummary(results: results)
        if summary.isTotalFailure { throw ActionError.failed(summary.failureText) }
        return summary.isWarning ? .warning(summary.message) : .message(summary.message)
    }
}
