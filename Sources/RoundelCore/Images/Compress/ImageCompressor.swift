import Foundation
import CoreGraphics
import ImageIO

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
    /// How long Strong's quality search may take for one file before it gives up and uses the fixed number. Five trials on a
    /// megapixel take a few seconds even for HEIC, so this only matters for a pathologically slow encoder.
    public static let defaultAdaptiveBudget = Duration.seconds(20)
    /// What the output is called: "<name> compressed.<ext>".
    static let nameSuffix = " compressed"

    private let encoder: any ImageEncoder
    private let probe: any ImageProbing
    private let plan: ConcurrencyPlan
    private let fileExists: @Sendable (URL) -> Bool
    private let pngOptimizer: @Sendable (Data, PNGOptimizer.Options) throws -> Data
    private let adaptiveBudget: Duration

    public init(encoder: any ImageEncoder, probe: any ImageProbing = ImageIOProbe(), plan: ConcurrencyPlan = .standard,
                fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
                pngOptimizer: @escaping @Sendable (Data, PNGOptimizer.Options) throws -> Data = { try PNGOptimizer.optimize($0, options: $1) },
                adaptiveBudget: Duration = ImageCompressor.defaultAdaptiveBudget) {
        self.encoder = encoder
        self.probe = probe
        self.plan = plan
        self.fileExists = fileExists
        self.pngOptimizer = pngOptimizer
        self.adaptiveBudget = adaptiveBudget
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

        let facts = probe.facts(of: source, detectedType: type)
        let decision = CompressionPlan.decide(facts, options: options)
        switch decision {
        case .skip(let reason): return .skipped(source: source, reason: reason)
        case .alreadyOptimal: return .alreadyOptimal(source: source)
        default: break
        }

        let slot = await placer.reserve(for: source, fileExtension: CompressionPlan.outputExtension(detectedType: type, source: source))
        var reducedToColors: Int?
        do {
            reducedToColors = try produce(decision, from: source, to: slot.temporary, stripMetadata: options.stripsMetadata)
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
        let changes = CompressionChanges(metadataRemoved: options.stripsMetadata, extrasRemoved: facts.auxiliaryData,   // a file with extras only gets here if they were allowed to go
                                    reducedToColors: reducedToColors)
        // Not worth keeping unless it saves enough.
        guard Double(after) <= Double(before) * (1 - Self.minimumSaving) else {
            try? FileManager.default.removeItem(at: slot.temporary)
            return .alreadyOptimal(source: source)
        }

        switch await placer.moveIntoPlace(slot, source: source, fileExtension: slot.target.pathExtension) {
        case .success(let output):
            return .compressed(source: source, output: output, bytesBefore: before, bytesAfter: after, changes: changes)
        case .failure(let failure): return .failed(source: source, message: failure.message)
        }
    }

    private struct SkipRequest: Error { let reason: CompressionSkipReason }
    private struct NothingToKeep: Error {}

    /// Writes the compressed version to `temporary`.
    /// - Returns: for a PNG that was reduced to a palette, its number of colors.
    @discardableResult
    private func produce(_ decision: CompressionDecision, from source: URL, to temporary: URL, stripMetadata: Bool) throws -> Int? {
        switch decision {
        case .reencode(let format, let options):
            _ = try encoder.encode(source: source, to: temporary, format: format, options: options)
        case .reencodeAdaptive(let format, let options, let range):
            try encodeAdaptively(source: source, to: temporary, format: format, options: options, range: range)
        case .optimizePNG(let options, let reduceColors):
            let data = try Data(contentsOf: source)
            do {
                let optimized = try pngOptimizer(data, options)
                // Strong: a reduced palette, if it is clearly smaller and passes every guard (see PNGColorReducer); else the lossless file.
                if reduceColors, let reduced = PNGColorReducer.reduce(source: data, lossless: optimized, stripMetadata: options.stripMetadata).result {
                    try reduced.data.write(to: temporary)
                    return reduced.colors
                }
                try optimized.write(to: temporary)
                return nil
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
        return nil
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    // MARK: Strong's quality search

    /// Trial encodes of a crop at different qualities, each scored against the crop; then one full encode at the lowest quality
    /// that reached `AdaptiveSearch.target`. See `AdaptiveSearch` for the rules.
    private func encodeAdaptively(source: URL, to temporary: URL, format: ImageFormat, options: ImageEncodingOptions, range: ClosedRange<Int>) throws {
        let started = ContinuousClock.now
        var final = options
        if let image = Self.decodeFirstImage(at: source) {
            let rect = AdaptiveSearch.cropRect(width: image.width, height: image.height)
            let crop = rect.size == CGSize(width: image.width, height: image.height) ? image : image.cropping(to: rect)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-adaptive-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: work) }
            if let crop, (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil {
                let cropFile = work.appendingPathComponent("crop.png")
                if Self.writePNG(crop, to: cropFile) {
                    let reference = ImagePixels.rgba8(crop)
                    let trial = work.appendingPathComponent("trial")
                    let outcome = AdaptiveSearch.search(range: range) { percent in
                        guard ContinuousClock.now - started < adaptiveBudget else { return nil }   // out of time
                        defer { try? FileManager.default.removeItem(at: trial) }
                        var o = options
                        o.quality = Double(percent) / 100
                        o.maxDimension = nil
                        guard (try? encoder.encode(source: cropFile, to: trial, format: format, options: o)) != nil,
                              let decoded = Self.decodeFirstImage(at: trial), decoded.width == crop.width, decoded.height == crop.height else { return nil }
                        return ImageMetrics.similarity(reference, ImagePixels.rgba8(decoded), width: crop.width, height: crop.height) >= AdaptiveSearch.target
                    }
                    if outcome.completedTrials > 0 { final.quality = Double(outcome.quality) / 100 }
                }
            }
        }
        // `final.quality` is still the fixed fallback (inside the range by construction) if the search could not run at all.
        _ = try encoder.encode(source: source, to: temporary, format: format, options: final)
    }

    private static func decodeFirstImage(at url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, CGImageSourceGetPrimaryImageIndex($0), nil) }
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let sink = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(sink, image, nil)
        return CGImageDestinationFinalize(sink)
    }
}
