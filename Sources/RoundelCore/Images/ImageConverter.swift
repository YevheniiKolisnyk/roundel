import Foundation

/// Converts a batch of files.
public protocol ImageConverting: Sendable {
    /// - Parameter progress: called once per finished file with `(done, total)`, from any thread.
    /// - Returns: one result per input file, in the same order.
    func convert(files: [URL], to format: ImageFormat, options: ImageEncodingOptions, progress: @escaping @Sendable (Int, Int) -> Void) async -> [ConversionItemResult]
}

/// Runs conversions with limited concurrency. For every file: detect the source type by content, skip files already
/// in the target format, pick an output name that is free (reserved up front so parallel files never choose the same
/// one), encode into a temporary file next to the source, and move it into place without ever replacing anything.
/// Originals are never modified or deleted.
public final class ImageConverter: ImageConverting, Sendable {
    private let encoder: any ImageEncoder
    private let plan: ConcurrencyPlan
    private let probe: any ImageProbing
    private let fileExists: @Sendable (URL) -> Bool

    public init(encoder: any ImageEncoder, maxConcurrent: Int = ConcurrencyPlan.standard.maxConcurrent,
                pixelBudget: Int = ConcurrencyPlan.standard.pixelBudget, probe: any ImageProbing = ImageIOProbe(),
                fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.encoder = encoder
        self.plan = ConcurrencyPlan(maxConcurrent: maxConcurrent, pixelBudget: pixelBudget)
        self.probe = probe
        self.fileExists = fileExists
    }

    public func convert(files: [URL], to format: ImageFormat, options: ImageEncodingOptions, progress: @escaping @Sendable (Int, Int) -> Void) async -> [ConversionItemResult] {
        let placer = OutputPlacer(fileExists: fileExists)
        let probe = self.probe
        let results = await BatchRunner.run(count: files.count, plan: plan, weight: { probe.pixelCount(of: files[$0]) }, work: { index in
            await self.convertOne(files[index], to: format, options: options, placer: placer)
        }, progress: progress)
        return results.enumerated().map { $0.element ?? .failed(source: files[$0.offset], message: "cancelled") }
    }

    // MARK: One file

    private func convertOne(_ source: URL, to format: ImageFormat, options: ImageEncodingOptions, placer: OutputPlacer) async -> ConversionItemResult {
        if Task.isCancelled { return .failed(source: source, message: "cancelled") }
        guard FileManager.default.fileExists(atPath: source.path) else { return .failed(source: source, message: "file not found") }
        guard FileManager.default.isReadableFile(atPath: source.path) else { return .failed(source: source, message: FailureText.cannotRead) }
        guard let type = encoder.detectType(of: source) else { return .failed(source: source, message: ImageConversionError.notAnImage.message) }
        if ImageFormats.isSame(detectedType: type, as: format) { return .skipped(source: source, reason: .alreadyInFormat) }
        // The output goes next to the source, so that folder must accept new files. Said up front, in plain words,
        // instead of as whatever the encoder makes of a failed write.
        guard FileManager.default.isWritableFile(atPath: source.deletingLastPathComponent().path) else {
            return .failed(source: source, message: FailureText.cannotWriteHere)
        }

        let slot = await placer.reserve(for: source, fileExtension: format.fileExtension)
        let temporary = slot.temporary

        let outcome: EncodeOutcome
        do {
            outcome = try encoder.encode(source: source, to: temporary, format: format, options: options)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return .failed(source: source, message: FailureText.describe(error))
        }

        // An encoder that says "done" must have left something behind; an empty or missing file is a failure, not a result.
        let written = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
        guard written > 0 else {
            try? FileManager.default.removeItem(at: temporary)
            return .failed(source: source, message: ImageConversionError.noOutput(format: format.displayName).message)
        }

        // Move into place. If the name was taken in the meantime, move on to the next free one: a file is never replaced.
        switch await placer.moveIntoPlace(slot, source: source, fileExtension: format.fileExtension) {
        case .success(let destination): return .converted(source: source, output: destination, notes: outcome.notes)
        case .failure(let failure): return .failed(source: source, message: failure.message)
        }
    }

}
