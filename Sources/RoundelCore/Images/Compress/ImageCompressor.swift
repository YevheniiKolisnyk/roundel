import Foundation

/// Compresses a batch of files.
public protocol ImageCompressing: Sendable {
    /// - Parameter progress: called once per finished file with `(done, total)`, from any thread.
    /// - Returns: one result per input file, in the same order.
    func compress(files: [URL], options: CompressionOptions, progress: @escaping @Sendable (Int, Int) -> Void) async -> [CompressionItemResult]
}

/// Compresses images next to the originals, as "<name> compressed.<ext>". For every file: find its type by content, decide
/// what to do (`CompressionPlan`), write into a hidden temporary file, keep the result only if it is at least
/// `minimumSaving` smaller, and move it into place without ever replacing anything. Originals are never modified or
/// deleted, and a failed or useless attempt leaves no file behind.
public final class ImageCompressor: ImageCompressing, Sendable {
    /// A result must save at least this share of the original, or it is not worth a new file ("already optimal").
    public static let minimumSaving = 0.02
    /// What the output is called: "<name> compressed.<ext>".
    static let nameSuffix = " compressed"

    private let encoder: any ImageEncoder
    private let probe: any ImageProbing
    private let plan: ConcurrencyPlan
    private let fileExists: @Sendable (URL) -> Bool
    private let pngOptimizer: @Sendable (Data, PNGOptimizer.Options) throws -> Data

    public init(encoder: any ImageEncoder, probe: any ImageProbing = ImageIOProbe(), plan: ConcurrencyPlan = .standard,
                fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
                pngOptimizer: @escaping @Sendable (Data, PNGOptimizer.Options) throws -> Data = { try PNGOptimizer.optimize($0, options: $1) }) {
        self.encoder = encoder
        self.probe = probe
        self.plan = plan
        self.fileExists = fileExists
        self.pngOptimizer = pngOptimizer
    }

    public func compress(files: [URL], options: CompressionOptions, progress: @escaping @Sendable (Int, Int) -> Void) async -> [CompressionItemResult] {
        let placer = OutputPlacer(suffix: Self.nameSuffix, fileExists: fileExists)
        let probe = self.probe
        let results = await BatchRunner.run(count: files.count, plan: plan, weight: { probe.pixelCount(of: files[$0]) }, work: { index in
            await self.compressOne(files[index], options: options, placer: placer)
        }, progress: progress)
        return results.enumerated().map { $0.element ?? .failed(source: files[$0.offset], message: "cancelled") }
    }

    // MARK: One file

    private func compressOne(_ source: URL, options: CompressionOptions, placer: OutputPlacer) async -> CompressionItemResult {
        if Task.isCancelled { return .failed(source: source, message: "cancelled") }
        guard FileManager.default.fileExists(atPath: source.path) else { return .failed(source: source, message: "file not found") }
        guard FileManager.default.isReadableFile(atPath: source.path) else { return .failed(source: source, message: FailureText.cannotRead) }
        guard let type = encoder.detectType(of: source) else { return .failed(source: source, message: ImageConversionError.notAnImage.message) }
        guard FileManager.default.isWritableFile(atPath: source.deletingLastPathComponent().path) else {
            return .failed(source: source, message: FailureText.cannotWriteHere)
        }

        let decision = CompressionPlan.decide(probe.facts(of: source, detectedType: type), options: options)
        switch decision {
        case .skip(let reason): return .skipped(source: source, reason: reason)
        case .alreadyOptimal: return .alreadyOptimal(source: source)
        default: break
        }

        let slot = await placer.reserve(for: source, fileExtension: CompressionPlan.outputExtension(detectedType: type, source: source))
        do {
            try produce(decision, from: source, to: slot.temporary)
        } catch is NothingToKeep {
            // The optimizer's own safety net refused its result: the original stays, nothing is written, and the user is not
            // bothered with an internal problem.
            try? FileManager.default.removeItem(at: slot.temporary)
            return .alreadyOptimal(source: source)
        } catch let skip as SkipRequest {
            try? FileManager.default.removeItem(at: slot.temporary)
            return .skipped(source: source, reason: skip.reason)
        } catch {
            try? FileManager.default.removeItem(at: slot.temporary)
            return .failed(source: source, message: FailureText.describe(error))
        }

        // An encoder that says "done" must have left something behind.
        let after = Self.fileSize(slot.temporary)
        let before = Self.fileSize(source)
        guard after > 0 else {
            try? FileManager.default.removeItem(at: slot.temporary)
            return .failed(source: source, message: "the compressor produced no output")
        }
        // Not worth keeping unless it saves enough.
        guard Double(after) <= Double(before) * (1 - Self.minimumSaving) else {
            try? FileManager.default.removeItem(at: slot.temporary)
            return .alreadyOptimal(source: source)
        }

        switch await placer.moveIntoPlace(slot, source: source, fileExtension: slot.target.pathExtension) {
        case .success(let output): return .compressed(source: source, output: output, bytesBefore: before, bytesAfter: after)
        case .failure(let failure): return .failed(source: source, message: failure.message)
        }
    }

    private struct SkipRequest: Error { let reason: CompressionSkipReason }
    private struct NothingToKeep: Error {}

    /// Writes the compressed version to `temporary`.
    private func produce(_ decision: CompressionDecision, from source: URL, to temporary: URL) throws {
        switch decision {
        case .reencode(let format, let options):
            _ = try encoder.encode(source: source, to: temporary, format: format, options: options)
        case .optimizePNG(let options):
            let data = try Data(contentsOf: source)
            do {
                try pngOptimizer(data, options).write(to: temporary)
            } catch let error as PNGOptimizeError {
                switch error {
                case .interlaced: throw SkipRequest(reason: .interlacedPNG)
                case .animated: throw SkipRequest(reason: .animated)
                case .damaged: throw ImageConversionError.damaged
                case .notPNG: throw ImageConversionError.notAnImage
                case .unsupported: throw SkipRequest(reason: .unsupported("this PNG"))
                case .verificationFailed: throw NothingToKeep()
                }
            }
        case .skip, .alreadyOptimal:
            break
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }
}
