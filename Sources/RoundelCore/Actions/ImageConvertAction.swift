import Foundation

/// Converts the dropped images to another format, next to the originals. See `ImageConverter` for the rules.
public struct ImageConvertAction: Action {
    public let id = "image.convert"
    public let title = "Convert Image"
    public let defaultIcon: Icon = .symbol("photo.on.rectangle.angled")
    public var acceptedInputs: Set<ActionInput> { [.files] }
    public var paramRules: ParamRules {
        ParamRules(specs: [.string("format", required: true, allowed: ImageFormats.catalog.map(\.key)), .number("quality", range: 0...1), .bool("lossless")])
    }

    private let converter: any ImageConverting
    private let capabilities: any ImageCapabilities

    public init(converter: any ImageConverting, capabilities: any ImageCapabilities) {
        self.converter = converter
        self.capabilities = capabilities
    }

    public func extraValidation(_ params: Params) -> [ParamIssue] {
        guard let format = params.string("format").flatMap(ImageFormats.format(forKey:)) else { return [] }
        if !capabilities.writableTypeIdentifiers.contains(format.typeIdentifier) {
            return [ParamIssue(message: "this Mac cannot write \(format.displayName)", blocksRun: true)]
        }
        var notes: [ParamIssue] = []
        if params.double("quality") != nil, !format.isLossy {
            notes.append(ParamIssue(message: "\"quality\" is ignored for \(format.displayName)", blocksRun: false))
        }
        if params.bool("lossless") == true, !format.hasLosslessMode {
            notes.append(ParamIssue(message: "\"lossless\" is ignored for \(format.displayName)", blocksRun: false))
        }
        return notes
    }

    /// Half a minute of headroom, plus half a minute per file (big HEIC or TIFF files take a while), at most an hour.
    public func timeout(for params: Params, fileCount: Int) -> Duration {
        .seconds(min(3600, 30 + 30 * max(fileCount, 1)))
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard !context.files.isEmpty else { throw ActionError.failed("no files to convert") }
        guard let format = context.params.string("format").flatMap(ImageFormats.format(forKey:)) else {
            throw ActionError.failed("format must be one of: \(ImageFormats.catalog.map(\.key).joined(separator: ", "))")
        }

        let options = ImageEncodingOptions(
            quality: format.isLossy ? context.params.double("quality") : nil,
            lossless: format.hasLosslessMode && context.params.bool("lossless") == true
        )
        let report = context.reportProgress
        let showsProgress = context.files.count > 1
        let results = await converter.convert(files: context.files, to: format, options: options) { done, total in
            if showsProgress { report(ConversionSummary.progressMessage(done: done, total: total)) }
        }

        // Every dropped file must come back as converted, skipped or failed; anything else would read as "nothing to do".
        guard results.count == context.files.count else {
            throw ActionError.failed("the converter reported on \(results.count) of \(context.files.count) files")
        }
        let summary = ConversionSummary(results: results, format: format)
        if summary.isTotalFailure { throw ActionError.failed(summary.failureText) }
        return summary.isWarning ? .warning(summary.message) : .message(summary.message)
    }
}
