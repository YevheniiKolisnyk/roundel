import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import RoundelCore

/// The whole compress pipeline on generated files in a temporary directory.
final class ImageCompressorTests: TempDirTestCase {
    private let compressor = ImageCompressor(encoder: ImageIOEncoder())
    private func compress(_ files: [URL], _ options: CompressionOptions = CompressionOptions()) async -> [CompressionItemResult] {
        await compressor.compress(files: files, options: options, progress: { _, _ in })
    }

    /// A "camera" JPEG: structured picture, high quality, with location and orientation.
    private func cameraJPEG(_ name: String = "photo.jpg", width: Int = 640, height: Int = 480, quality: Double = 0.92, properties: [CFString: Any] = [:]) throws -> URL {
        try TestImages.write(TestImages.photo(width: width, height: height, grain: 3), as: "public.jpeg", to: dir.appendingPathComponent(name), quality: quality, properties: properties)
    }

    // MARK: JPEG

    func testAHighQualityJPEGIsCompressedNextToTheOriginalWhichStaysUntouched() async throws {
        let source = try cameraJPEG()
        let original = try Data(contentsOf: source)
        let results = await compress([source])
        guard case .compressed(let src, let output, let before, let after, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(src, source)
        XCTAssertEqual(output.lastPathComponent, "photo compressed.jpg")
        XCTAssertEqual(output.deletingLastPathComponent(), dir)
        XCTAssertEqual(before, original.count)
        XCTAssertEqual(after, size(output))
        XCTAssertLessThanOrEqual(Double(after), Double(before) * 0.98, "at least 2% smaller")
        XCTAssertEqual(try Data(contentsOf: source), original, "the original is byte for byte what it was")
        XCTAssertEqual(listing(), ["photo compressed.jpg", "photo.jpg"], "no temporary files left")
        let image = try TestImages.load(output)
        XCTAssertEqual(image.width, 640); XCTAssertEqual(image.height, 480)
    }

    func testTheDefaultKeepsLocationAndOrientationAndStripMetadataRemovesTheLocation() async throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 50.45, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 30.52, kCGImagePropertyGPSLongitudeRef: "E"]
        let source = try cameraJPEG(properties: [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyOrientation: 6])
        guard case .compressed(_, let kept, _, _, _)? = await compress([source]).first else { return XCTFail() }
        XCTAssertNotNil(TestImages.properties(of: kept)[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(TestImages.properties(of: kept)[kCGImagePropertyOrientation] as? Int, 6)

        guard case .compressed(_, let stripped, _, _, _)? = await compress([source], CompressionOptions(stripMetadata: true)).first else { return XCTFail() }
        XCTAssertNil(TestImages.properties(of: stripped)[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(TestImages.properties(of: stripped)[kCGImagePropertyOrientation] as? Int, 6)
    }

    func testMaxDimensionShrinksThePicture() async throws {
        let source = try cameraJPEG()
        guard case .compressed(_, let output, _, _, _)? = await compress([source], CompressionOptions(maxDimension: 320)).first else { return XCTFail() }
        XCTAssertEqual(try TestImages.load(output).width, 320)
    }

    func testANameTakenByAnEarlierCompressedCopyGetsANumberAndTheEarlierOneIsUntouched() async throws {
        let source = try cameraJPEG()
        let earlier = dir.appendingPathComponent("photo compressed.jpg")
        try Data("do not touch".utf8).write(to: earlier)
        guard case .compressed(_, let output, _, _, _)? = await compress([source]).first else { return XCTFail() }
        XCTAssertEqual(output.lastPathComponent, "photo compressed 2.jpg")
        XCTAssertEqual(try Data(contentsOf: earlier), Data("do not touch".utf8))
    }

    func testAnAlreadyHeavilyCompressedJPEGIsAlreadyOptimalAndLeavesNothingBehind() async throws {
        let source = try cameraJPEG("low.jpg", quality: 0.25)
        let results = await compress([source])
        XCTAssertEqual(results, [.alreadyOptimal(source: source)])
        XCTAssertEqual(listing(), ["low.jpg"])
    }

    func testTheOutputExtensionFollowsTheContent() async throws {
        let png = dir.appendingPathComponent("really-a-png.jpg")
        try TestImages.write(TestImages.photo(width: 200, height: 150), as: "public.png", to: png)
        guard case .compressed(_, let output, _, _, _)? = await compress([png]).first else { return XCTFail() }
        XCTAssertEqual(output.lastPathComponent, "really-a-png compressed.png")
    }

    // MARK: PNG

    func testAPNGIsOptimizedLosslesslyAndBecomesSmaller() async throws {
        let source = try TestImages.write(TestImages.photo(width: 300, height: 200, grain: 0), as: "public.png", to: dir.appendingPathComponent("shot.png"))
        guard case .compressed(_, let output, let before, let after, _)? = await compress([source]).first else { return XCTFail() }
        XCTAssertEqual(output.lastPathComponent, "shot compressed.png")
        XCTAssertLessThan(after, before)
        XCTAssertEqual(TestImages.rgba(try TestImages.load(output)), TestImages.rgba(try TestImages.load(source)), "same pixels")
        XCTAssertEqual(listing(), ["shot compressed.png", "shot.png"])
    }

    func testAPNGThatIsAlreadyOptimalIsLeftAlone() async throws {
        let source = try TestImages.write(TestImages.photo(width: 120, height: 80), as: "public.png", to: dir.appendingPathComponent("a.png"))
        guard case .compressed(_, let output, _, _, _)? = await compress([source]).first else { return XCTFail() }
        // Optimizing the optimized copy again gains nothing.
        let again = await compress([output])
        XCTAssertEqual(again, [.alreadyOptimal(source: output)])
        XCTAssertEqual(listing(), ["a compressed.png", "a.png"])
    }

    func testAnInterlacedPNGIsSkippedWithItsReason() async throws {
        let url = dir.appendingPathComponent("i.png")
        try TestPNG.make(.init(width: 8, height: 8, colorType: 2, bitDepth: 8, sample: { x, _, _ in x }, interlace: 1)).write(to: url)
        // ImageIO may not read a hand-made interlaced file; if it does not, the file is "not an image" rather than skipped.
        let result = await compress([url]).first
        if case .skipped(_, let reason)? = result { XCTAssertEqual(reason, .interlacedPNG) } else if case .failed? = result { XCTAssertEqual(listing(), ["i.png"]) } else { XCTFail("\(String(describing: result))") }
    }

    // MARK: Skipped

    func testAStaticGIFAndAnAnimatedGIFAreSkippedWithTheirMessages() async throws {
        let still = try TestImages.write(TestImages.photo(width: 60, height: 40), as: "com.compuserve.gif", to: dir.appendingPathComponent("still.gif"))
        let anim = dir.appendingPathComponent("anim.gif")
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(anim as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for i in 0..<2 { CGImageDestinationAddImage(sink, TestImages.photo(width: 40, height: 30, seed: UInt32(i + 3)), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let results = await compress([still, anim])
        XCTAssertEqual(results, [.skipped(source: still, reason: .useConvert("GIF")), .skipped(source: anim, reason: .animated)])
        XCTAssertEqual(listing(), ["anim.gif", "still.gif"])
    }

    func testAJPEGWithDepthDataIsSkipped() async throws {
        let out = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, TestImages.photo(width: 200, height: 150), [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        var half = [Float16](repeating: 0.5, count: 64)
        CGImageDestinationAddAuxiliaryDataInfo(sink, kCGImageAuxiliaryDataTypeDisparity, [kCGImageAuxiliaryDataInfoData: Data(bytes: &half, count: 128),
            kCGImageAuxiliaryDataInfoDataDescription: [kCGImagePropertyWidth: 8, kCGImagePropertyHeight: 8, kCGImagePropertyBytesPerRow: 16, kCGImagePropertyPixelFormat: 0x68646973 as UInt32]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let url = dir.appendingPathComponent("portrait.jpg")
        try (out as Data).write(to: url)
        let depth = await compress([url])
        XCTAssertEqual(depth, [.skipped(source: url, reason: .hasAuxiliaryData([.disparity]))])
    }

    // MARK: Failures

    func testBrokenInputsFailWithReadableMessagesAndDoNotStopTheOthers() async throws {
        let good = try cameraJPEG("good.jpg")
        let text = dir.appendingPathComponent("notes.jpg")
        try Data("this is not an image".utf8).write(to: text)
        let missing = dir.appendingPathComponent("gone.jpg")
        let truncated = dir.appendingPathComponent("cut.png")
        let png = try TestImages.write(TestImages.photo(width: 100, height: 80), as: "public.png", to: dir.appendingPathComponent("whole.png"))
        let whole = try Data(contentsOf: png)
        try Data(whole.prefix(whole.count * 9 / 10)).write(to: truncated)

        let results = await compress([text, missing, truncated, good])
        XCTAssertEqual(results[0], .failed(source: text, message: "not an image"))
        XCTAssertEqual(results[1], .failed(source: missing, message: "file not found"))
        if case .failed(_, let message) = results[2] { XCTAssertEqual(message, "damaged or incomplete") } else { XCTFail("\(results[2])") }
        if case .compressed = results[3] {} else { XCTFail("the good one still goes through: \(results[3])") }
        XCTAssertFalse(listing().contains { $0.hasSuffix(".tmp") })
    }

    func testAFolderThatCannotBeWrittenToFailsInPlainWords() async throws {
        let source = try cameraJPEG()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let results = await compress([source])
        XCTAssertEqual(results, [.failed(source: source, message: FailureText.cannotWriteHere)])
    }

    func testAnEncoderThatThrowsOrLeavesNothingLeavesNothingBehind() async throws {
        let source = try cameraJPEG()
        for encoder in [StubEncoder(behavior: .throwing), StubEncoder(behavior: .empty), StubEncoder(behavior: .silent)] {
            let stubbed = ImageCompressor(encoder: encoder, probe: StubProbe(type: "public.jpeg", ijg: 95))
            let results = await stubbed.compress(files: [source], options: CompressionOptions(), progress: { _, _ in })
            guard case .failed(_, let message)? = results.first else { return XCTFail("\(encoder.behavior): \(results)") }
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains(".roundel-"), "no internal names: \(message)")
            XCTAssertEqual(listing(), ["photo.jpg"], "\(encoder.behavior)")
        }
    }

    // MARK: The 2% rule

    func testTheResultIsKeptOnlyIfItSavesAtLeastTwoPercent() async throws {
        let source = dir.appendingPathComponent("s.jpg")
        try Data(repeating: 1, count: 100_000).write(to: source)
        func attempt(_ outputSize: Int) async -> CompressionItemResult {
            let stub = ImageCompressor(encoder: StubEncoder(behavior: .writes(outputSize)), probe: StubProbe(type: "public.jpeg", ijg: 95))
            return await stub.compress(files: [source], options: CompressionOptions(), progress: { _, _ in })[0]
        }
        XCTAssertEqual(ImageCompressor.minimumSaving, 0.02)
        if case .compressed(_, _, _, let after, _) = await attempt(98_000) { XCTAssertEqual(after, 98_000, "exactly 2% is enough") } else { XCTFail("98000 of 100000 saves 2%") }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("s compressed.jpg"))
        let almost = await attempt(98_001), same = await attempt(100_000), bigger = await attempt(120_000)
        XCTAssertEqual(almost, .alreadyOptimal(source: source), "1.999% is not")
        XCTAssertEqual(same, .alreadyOptimal(source: source))
        XCTAssertEqual(bigger, .alreadyOptimal(source: source), "bigger is not kept")
        XCTAssertEqual(listing(), ["s.jpg"], "and the temporary file is deleted each time")
    }

    // MARK: Batch behaviour

    func testProgressCountsEveryFileAndResultsKeepTheirOrder() async throws {
        let files = try (1...5).map { try cameraJPEG("p\($0).jpg", width: 160, height: 120) }
        let steps = StepLog()
        let results = await compressor.compress(files: files, options: CompressionOptions(), progress: { done, total in steps.add(done, total) })
        XCTAssertEqual(steps.values.map(\.0), [1, 2, 3, 4, 5])
        XCTAssertTrue(steps.values.allSatisfy { $0.1 == 5 })
        XCTAssertEqual(results.compactMap { result -> URL? in if case .compressed(let s, _, _, _, _) = result { return s } else { return nil } }, files)
    }

    func testSmallFilesRunThreeAtATimeAndHugeOnesOneAtATime() async throws {
        let files = try (1...6).map { index -> URL in let u = dir.appendingPathComponent("f\(index).jpg"); try Data(repeating: 1, count: 1000).write(to: u); return u }
        for (pixels, expectedPeak) in [(5_000_000, 3), (80_000_000, 1)] {
            let encoder = StubEncoder(behavior: .slow(output: 500))
            let stubbed = ImageCompressor(encoder: encoder, probe: StubProbe(type: "public.jpeg", ijg: 95, pixels: pixels))
            _ = await stubbed.compress(files: files, options: CompressionOptions(), progress: { _, _ in })
            XCTAssertEqual(encoder.peak, expectedPeak, "\(pixels) pixels each")
            for file in files { try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(file.deletingPathExtension().lastPathComponent) compressed.jpg")) }
        }
    }
}

// MARK: Test doubles

private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [(Int, Int)] = []
    var values: [(Int, Int)] { lock.withLock { _values } }
    func add(_ done: Int, _ total: Int) { lock.withLock { _values.append((done, total)) } }
}

private struct StubProbe: ImageProbing {
    var type: String
    var ijg: Int?
    var pixels = 1_000_000
    func facts(of url: URL, detectedType: String) -> ImageFacts { ImageFacts(detectedType: detectedType, jpegQualityIJG: ijg) }
    func pixelCount(of url: URL) -> Int { pixels }
}

private final class StubEncoder: ImageEncoder, @unchecked Sendable {
    enum Behavior: CustomStringConvertible, Equatable {
        case throwing, empty, silent, writes(Int), slow(output: Int)
        var description: String { "\(self)" }
    }
    let behavior: Behavior
    private let lock = NSLock()
    private var running = 0
    private(set) var peak = 0
    init(behavior: Behavior) { self.behavior = behavior }

    func detectType(of url: URL) -> String? { "public.jpeg" }

    func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
        lock.withLock { running += 1; peak = max(peak, running) }
        defer { lock.withLock { running -= 1 } }
        switch behavior {
        case .throwing: throw NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom \(destination.lastPathComponent)"])
        case .empty: try Data().write(to: destination)
        case .silent: break
        case .writes(let n): try Data(repeating: 2, count: n).write(to: destination)
        case .slow(let n):
            Thread.sleep(forTimeInterval: 0.05)
            try Data(repeating: 2, count: n).write(to: destination)
        }
        return EncodeOutcome()
    }
}
