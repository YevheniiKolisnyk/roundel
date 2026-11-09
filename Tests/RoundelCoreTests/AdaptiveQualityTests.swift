import XCTest
import CoreGraphics
@testable import RoundelCore

/// Strong's per-file quality search: the metric, the search itself, the crop it works on, and the whole thing on real files.
final class ImageMetricsTests: XCTestCase {
    private func rgba(_ w: Int, _ h: Int, _ f: (Int, Int) -> (Int, Int, Int)) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let (r, g, b) = f(x, y)
            let i = (y * w + x) * 4
            out[i] = UInt8(max(0, min(255, r))); out[i + 1] = UInt8(max(0, min(255, g))); out[i + 2] = UInt8(max(0, min(255, b)))
        } }
        return out
    }

    private let w = 96, h = 64

    private func texture(_ x: Int, _ y: Int) -> Int { 128 + Int(60 * sin(Double(x) * 0.5) * cos(Double(y) * 0.4)) + (x * 7 + y * 13) % 11 }

    func testIdenticalPicturesAreIdentical() {
        let a = rgba(w, h) { x, y in let t = texture(x, y); return (t, t / 2 + 20, 255 - t) }
        XCTAssertEqual(ImageMetrics.similarity(a, a, width: w, height: h), 1, accuracy: 1e-9)
        XCTAssertEqual(ImageMetrics.lumaSSIM(a, a, width: w, height: h), 1, accuracy: 1e-9)
    }

    func testMoreNoiseMeansLessSimilar() {
        let a = rgba(w, h) { x, y in let t = texture(x, y); return (t, t, t) }
        var noise = TestNoise(state: 4)
        let mild = rgba(w, h) { x, y in let t = texture(x, y); return (t + noise.next() % 5 - 2, t + noise.next() % 5 - 2, t + noise.next() % 5 - 2) }
        let heavy = rgba(w, h) { x, y in let t = texture(x, y); return (t + noise.next() % 61 - 30, t + noise.next() % 61 - 30, t + noise.next() % 61 - 30) }
        let m = ImageMetrics.similarity(a, mild, width: w, height: h), v = ImageMetrics.similarity(a, heavy, width: w, height: h)
        XCTAssertGreaterThan(m, 0.9)
        XCTAssertLessThan(v, m)
        XCTAssertLessThan(v, 0.9)
    }

    func testAColorOnlyChangeIsCaughtEvenThoughTheLuminanceBarelyMoves() {
        // Same structure, but green and red/blue trade places in a way that keeps the luminance almost equal.
        let a = rgba(w, h) { x, y in let t = texture(x, y); return (t + 40, t - 25, t - 40) }
        let b = rgba(w, h) { x, y in let t = texture(x, y); return (t - 40, t + 31, t + 40) }
        let luma = ImageMetrics.lumaSSIM(a, b, width: w, height: h), all = ImageMetrics.similarity(a, b, width: w, height: h)
        XCTAssertLessThanOrEqual(all, luma + 1e-12, "the combined score is never above the luma score")
        let channels = (0..<3).map { ImageMetrics.channelSSIM(a, b, width: w, height: h, channel: $0) }
        XCTAssertEqual(all, min(luma, channels.reduce(0, +) / 3), accuracy: 1e-12, "min(luma SSIM, mean RGB SSIM)")
    }

    func testNoiseInOneChannelLowersTheLumaScoreBelowTheChannelMeanAndTheCombinedScoreFollowsTheLower() {
        // Noise in green only: luminance (mostly green) suffers, but two of the three channels are perfect, so their mean is higher.
        let a = rgba(w, h) { x, y in let t = texture(x, y); return (t, t, t) }
        var noise = TestNoise(state: 9)
        let b = rgba(w, h) { x, y in let t = texture(x, y); return (t, t + noise.next() % 41 - 20, t) }
        let luma = ImageMetrics.lumaSSIM(a, b, width: w, height: h)
        let mean = (0..<3).map { ImageMetrics.channelSSIM(a, b, width: w, height: h, channel: $0) }.reduce(0, +) / 3
        XCTAssertLessThan(luma, mean, "precondition of this test")
        XCTAssertEqual(ImageMetrics.similarity(a, b, width: w, height: h), luma, accuracy: 1e-12, "the lower of the two is the score")
    }

    func testTheScoreAgreesWithTheTestSuitesSSIMOnImages() throws {
        let a = TestImages.photo(width: 160, height: 120, grain: 2), b = TestImages.photo(width: 160, height: 120, grain: 14, seed: 5)
        let here = ImageMetrics.lumaSSIM(ImagePixels.rgba8(a), ImagePixels.rgba8(b), width: 160, height: 120)
        XCTAssertEqual(here, TestImages.ssim(a, b), accuracy: 0.01, "an independent implementation (8x8 windows, stride 4) says the same")
    }

    func testTooSmallOrMismatchedInputIsHandled() {
        XCTAssertEqual(ImageMetrics.similarity([], [], width: 0, height: 0), 1)
        let tiny = rgba(4, 4) { _, _ in (10, 20, 30) }
        XCTAssertEqual(ImageMetrics.similarity(tiny, tiny, width: 4, height: 4), 1, "smaller than one window: identical is identical")
        XCTAssertEqual(ImageMetrics.similarity(tiny, [], width: 4, height: 4), 0, "buffers that do not match the size score zero")
    }
}

final class AdaptiveSearchTests: XCTestCase {
    /// A made-up monotone quality -> score curve; records every quality that was tried.
    private func run(_ range: ClosedRange<Int>, passesFrom threshold: Int, maxTrials: Int = 5) -> (outcome: AdaptiveSearch.Outcome, tried: [Int]) {
        var tried: [Int] = []
        let outcome = AdaptiveSearch.search(range: range, maxTrials: maxTrials) { q in tried.append(q); return q >= threshold }
        return (outcome, tried)
    }

    func testTheLowestQualityIsTakenWhenItAlreadyPasses() {
        let r = run(30...55, passesFrom: 10)
        XCTAssertEqual(r.outcome.quality, 30)
        XCTAssertEqual(r.tried, [30], "one trial is enough")
        XCTAssertTrue(r.outcome.reachedTarget)
    }

    func testTheHighestAllowedQualityIsUsedWhenEvenThatMissesTheTarget() {
        let r = run(30...55, passesFrom: 90)
        XCTAssertEqual(r.outcome.quality, 55)
        XCTAssertEqual(r.tried, [30, 55])
        XCTAssertFalse(r.outcome.reachedTarget)
    }

    func testItBisectsToTheLowestPassingQualityWithinTheTrialBudget() {
        let r = run(30...70, passesFrom: 41)
        XCTAssertLessThanOrEqual(r.tried.count, 5, "at most five trials")
        XCTAssertGreaterThanOrEqual(r.outcome.quality, 41, "never below what passes")
        XCTAssertLessThanOrEqual(r.outcome.quality, 46, "and close to the edge with that few trials")
        XCTAssertTrue(r.outcome.reachedTarget)
    }

    func testEveryTrialStaysInsideTheRangeAndWithinTheBudgetForAnyThreshold() {
        for range in [30...55, 20...55, 30...70, 30...31, 40...40] {
            for threshold in range.lowerBound - 5...range.upperBound + 5 {
                let r = run(range, passesFrom: threshold)
                XCTAssertTrue(r.tried.allSatisfy(range.contains), "\(range) \(threshold)")
                XCTAssertLessThanOrEqual(r.tried.count, 5)
                XCTAssertTrue(range.contains(r.outcome.quality))
                if threshold <= range.upperBound { XCTAssertGreaterThanOrEqual(r.outcome.quality, max(threshold, range.lowerBound), "never a failing quality when a passing one was reachable") }
            }
        }
    }

    func testTheSameInputsGiveTheSameAnswer() {
        XCTAssertEqual(run(30...70, passesFrom: 52).tried, run(30...70, passesFrom: 52).tried)
        XCTAssertEqual(run(30...70, passesFrom: 52).outcome, run(30...70, passesFrom: 52).outcome)
    }

    func testAFailingTrialStopsTheSearchWithTheBestKnownPassingQuality() {
        var tried: [Int] = []
        let outcome = AdaptiveSearch.search(range: 30...70, maxTrials: 5) { q in tried.append(q); return tried.count == 3 ? nil : q >= 50 }
        XCTAssertEqual(tried.count, 3)
        XCTAssertEqual(outcome.quality, 70, "the safe end of the range: the only quality known to pass")
        XCTAssertTrue(outcome.stoppedEarly)
        // Nothing evaluable at all: the safe end too.
        XCTAssertEqual(AdaptiveSearch.search(range: 30...55, maxTrials: 5) { _ in nil }.quality, 55)
    }

    func testTheCropIsAboutOneMegapixelFromTheMiddleOrTheWholeImage() {
        XCTAssertEqual(AdaptiveSearch.cropRect(width: 4000, height: 3000), CGRect(x: 1488, y: 988, width: 1024, height: 1024))
        XCTAssertEqual(AdaptiveSearch.cropRect(width: 800, height: 600), CGRect(x: 0, y: 0, width: 800, height: 600), "smaller than the crop: the whole image")
        XCTAssertEqual(AdaptiveSearch.cropRect(width: 3000, height: 500), CGRect(x: 988, y: 0, width: 1024, height: 500))
        XCTAssertEqual(AdaptiveSearch.cropRect(width: 1024, height: 1024), CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }

    func testTheConstantsAreTheAgreedOnes() {
        XCTAssertEqual(AdaptiveSearch.target, 0.88)
        XCTAssertEqual(AdaptiveSearch.maxTrials, 5)
        XCTAssertEqual(AdaptiveSearch.range(forJPEG: nil), 30...55)
        XCTAssertEqual(AdaptiveSearch.heicRange, 20...55)
        XCTAssertEqual(AdaptiveSearch.webpRange, 30...70)
    }
}

/// Wraps an encoder and records every call, so tests can see how many encodes happened and on what.
private final class CountingEncoder: ImageEncoder, @unchecked Sendable {
    struct Call { let source: URL; let quality: Double?; let strip: Bool }
    private let inner = ImageIOEncoder()
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }
    func detectType(of url: URL) -> String? { inner.detectType(of: url) }
    func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
        lock.withLock { _calls.append(Call(source: source, quality: options.quality, strip: options.stripMetadata)) }
        return try inner.encode(source: source, to: destination, format: format, options: options)
    }
}

final class AdaptiveCompressionTests: TempDirTestCase {
    private func smooth(_ name: String = "smooth.jpg") throws -> URL {
        try TestImages.write(TestImages.photo(width: 640, height: 480, grain: 0), as: "public.jpeg", to: dir.appendingPathComponent(name), quality: 0.92)
    }
    private func textured(_ name: String = "textured.jpg") throws -> URL {
        // A picture with fine detail everywhere: grain plus a high-frequency pattern, which punishes low quality.
        let base = TestImages.photo(width: 640, height: 480, grain: 14, seed: 3)
        var pixels = TestImages.rgba(base)
        for y in 0..<480 { for x in 0..<640 {
            let t = Int(18 * sin(Double(x) * 0.9) * sin(Double(y) * 1.1))
            let i = (y * 640 + x) * 4
            for k in 0..<3 { pixels[i + k] = UInt8(max(0, min(255, Int(pixels[i + k]) + t))) }
        } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 640, height: 480, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 640 * 4, space: TestImages.srgb,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try TestImages.write(image, as: "public.jpeg", to: dir.appendingPathComponent(name), quality: 0.92)
    }

    private func strong(_ source: URL, encoder: CountingEncoder = CountingEncoder(), budget: Duration = .seconds(60)) async throws -> (output: URL, encoder: CountingEncoder) {
        let compressor = ImageCompressor(encoder: encoder, adaptiveBudget: budget)
        let results = await compressor.compress(files: [source], options: CompressionOptions(preset: .strong), progress: { _, _ in })
        guard case .compressed(_, let output, _, _, _)? = results.first else { XCTFail("\(results)"); throw CancellationError() }
        return (output, encoder)
    }

    private func finalQuality(_ encoder: CountingEncoder, source: URL) -> Double? { encoder.calls.last(where: { $0.source == source })?.quality }

    func testASmoothPictureGetsALowerQualityThanATexturedOneAndBothHoldTheTarget() async throws {
        let a = try smooth(), b = try textured()
        let s = try await strong(a), t = try await strong(b)
        let qs = try XCTUnwrap(finalQuality(s.encoder, source: a)), qt = try XCTUnwrap(finalQuality(t.encoder, source: b))
        XCTAssertLessThan(qs, qt, "smooth \(qs) vs textured \(qt): the search adapts")
        for (source, output) in [(a, s.output), (b, t.output)] {
            let score = ImageMetrics.similarity(ImagePixels.rgba8(try TestImages.load(source)), ImagePixels.rgba8(try TestImages.load(output)), width: 640, height: 480)
            XCTAssertGreaterThanOrEqual(score, 0.86, "\(source.lastPathComponent): \(score) (target 0.88 measured on a crop)")
        }
    }

    func testTheSearchUsesAtMostFiveSmallTrialsAndOneFullEncode() async throws {
        let source = try textured()
        let (_, encoder) = try await strong(source)
        let calls = encoder.calls
        XCTAssertLessThanOrEqual(calls.count, 6, "five trials and the final encode")
        XCTAssertGreaterThanOrEqual(calls.count, 2)
        XCTAssertEqual(calls.last?.source, source, "the last encode is the real one")
        XCTAssertTrue(calls.dropLast().allSatisfy { $0.source != source }, "trials run on a crop file, not on the original")
        XCTAssertTrue(calls.allSatisfy(\.strip), "Strong strips in every encode")
    }

    func testQualityNeverGoesBelowTheFloorEvenForAPictureThatNeverNeedsMore() async throws {
        let flat = try TestImages.write(TestImages.photo(width: 320, height: 240, grain: 0), as: "public.jpeg", to: dir.appendingPathComponent("flat.jpg"), quality: 0.95)
        let (_, encoder) = try await strong(flat)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(finalQuality(encoder, source: flat)), 0.30)
        XCTAssertTrue(encoder.calls.allSatisfy { ($0.quality ?? 1) >= 0.30 - 1e-9 }, "no trial below the floor either")
    }

    func testTheResultIsTheSameEveryTime() async throws {
        let source = try textured()
        let first = try await strong(source)
        let second = try await strong(source)
        XCTAssertEqual(try Data(contentsOf: first.output), try Data(contentsOf: second.output))
        XCTAssertEqual(finalQuality(first.encoder, source: source), finalQuality(second.encoder, source: source))
    }

    func testAnExhaustedTimeBudgetFallsBackToStrongsFixedNumberWithoutTrials() async throws {
        let source = try textured()
        let (_, encoder) = try await strong(source, budget: .zero)
        XCTAssertEqual(encoder.calls.count, 1, "no trial fit in the budget")
        XCTAssertEqual(try XCTUnwrap(finalQuality(encoder, source: source)), 0.35, accuracy: 1e-9, "Strong's fixed, worst-case-safe quality")
    }

    func testASizeLimitDoesNotStopTheSearch() async throws {
        // With maxDimension the final file is smaller, but the trials still run on the crop at full size and still find the floor
        // for a smooth picture (not the fixed fallback of 0.35).
        let source = try smooth()
        let encoder = CountingEncoder()
        let results = await ImageCompressor(encoder: encoder).compress(files: [source], options: CompressionOptions(preset: .strong, maxDimension: 320), progress: { _, _ in })
        guard case .compressed(_, let output, _, _, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(try TestImages.load(output).width, 320)
        XCTAssertEqual(try XCTUnwrap(finalQuality(encoder, source: source)), 0.30, accuracy: 1e-9)
    }

    func testOtherPresetsAndExplicitQualitiesDoNotSearch() async throws {
        let source = try textured()
        for options in [CompressionOptions(preset: .light), CompressionOptions(preset: .balanced), CompressionOptions(preset: .strong, quality: 0.5)] {
            let encoder = CountingEncoder()
            let results = await ImageCompressor(encoder: encoder).compress(files: [source], options: options, progress: { _, _ in })
            XCTAssertEqual(encoder.calls.count, 1, "\(options.preset) \(options.quality as Any)")
            if case .compressed(_, let output, _, _, _)? = results.first { try? FileManager.default.removeItem(at: output) }
        }
    }

    func testHEICIsSearchedToo() async throws {
        let source = try TestImages.write(TestImages.photo(width: 640, height: 480, grain: 2), as: "public.heic", to: dir.appendingPathComponent("p.heic"), quality: 0.9)
        let (output, encoder) = try await strong(source)
        let q = try XCTUnwrap(finalQuality(encoder, source: source))
        XCTAssertTrue((0.20...0.55).contains(q), "\(q)")
        XCTAssertLessThanOrEqual(encoder.calls.count, 6)
        XCTAssertGreaterThanOrEqual(ImageMetrics.similarity(ImagePixels.rgba8(try TestImages.load(source)), ImagePixels.rgba8(try TestImages.load(output)), width: 640, height: 480), 0.86)
    }

    func testNoTemporaryFilesAreLeftBehindAnywhere() async throws {
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
        let source = try textured()
        _ = try await strong(source)
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
        XCTAssertEqual(after.filter { $0.hasPrefix("roundel-adaptive") }, before.filter { $0.hasPrefix("roundel-adaptive") }, "the crop and trial files are removed")
        XCTAssertEqual(listing().filter { $0.hasSuffix(".tmp") }, [])
    }
}
