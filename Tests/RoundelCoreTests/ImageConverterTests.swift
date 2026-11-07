import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import RoundelCore

/// Real ImageIO on images generated in memory and written to a temporary directory. Nothing else on disk is touched.
final class ImageConverterTests: XCTestCase {
    private var dir: URL!
    private let converter = ImageConverter(encoder: ImageIOEncoder())

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-image-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Generated images

    private func makeImage(width: Int = 32, height: Int = 24, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
                           alpha: Bool = false, fill: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0.9, 0.2, 0.1, 1)) throws -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: info))
        context.setFillColor(red: fill.r, green: fill.g, blue: fill.b, alpha: fill.a)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func noisyImage(side: Int = 96) throws -> CGImage {
        var state: UInt32 = 12345
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<bytes.count {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes[i] = i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 24)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @discardableResult
    private func write(_ image: CGImage, as type: UTType, named name: String, properties: [CFString: Any] = [:]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func writeAnimatedGIF(named name: String, frames: Int = 3) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
        for i in 0..<frames {
            let shade = CGFloat(i) / CGFloat(frames)
            CGImageDestinationAddImage(destination, try makeImage(fill: (shade, 0.5, 1 - shade, 1)), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func detectedType(_ url: URL) -> String? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    private func properties(_ url: URL) -> [String: Any] {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
    }

    private func pixel(_ url: URL, x: Int = 0, y: Int = 0) throws -> (r: Int, g: Int, b: Int, a: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var data = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    private func format(_ key: String) -> ImageFormat { ImageFormats.format(forKey: key)! }

    private func convert(_ urls: [URL], to key: String, quality: Double? = nil) async -> [ConversionItemResult] {
        await converter.convert(files: urls, to: format(key), options: ImageEncodingOptions(quality: quality), progress: { _, _ in })
    }

    // MARK: Basics

    func testPngBecomesAJpegNextToTheSourceAndTheOriginalIsUntouched() async throws {
        let source = try write(try makeImage(), as: .png, named: "photo.png")
        let before = try Data(contentsOf: source)

        let results = await convert([source], to: "jpeg")

        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(output, dir.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(detectedType(output), "public.jpeg")
        XCTAssertEqual(try Data(contentsOf: source), before, "the original is never touched")
        XCTAssertEqual(try files(), ["photo.jpg", "photo.png"], "no temporary files are left behind")
    }

    func testDimensionsAreKept() async throws {
        let source = try write(try makeImage(width: 40, height: 17), as: .png, named: "a.png")
        _ = await convert([source], to: "tiff")
        let output = properties(dir.appendingPathComponent("a.tiff"))
        XCTAssertEqual(output[kCGImagePropertyPixelWidth as String] as? Int, 40)
        XCTAssertEqual(output[kCGImagePropertyPixelHeight as String] as? Int, 17)
    }

    func testEveryCommonFormatCanBeWrittenAndIsDetectedByContent() async throws {
        let source = try write(try makeImage(), as: .png, named: "src.png")
        let writable = Set(SystemImageCapabilities().writableTypeIdentifiers)
        for target in ImageFormats.catalog where target.key != "png" && writable.contains(target.typeIdentifier) {
            let results = await convert([source], to: target.key)
            guard case .converted(_, let output, _)? = results.first else { XCTFail("\(target.key): \(results)"); continue }
            XCTAssertEqual(detectedType(output), target.typeIdentifier, target.key)
        }
    }

    // MARK: Alpha

    func testTransparencyIsFlattenedOntoWhiteForJpeg() async throws {
        let source = try write(try makeImage(alpha: true, fill: (0, 0, 0, 0)), as: .png, named: "clear.png")
        _ = await convert([source], to: "jpeg")
        let p = try pixel(dir.appendingPathComponent("clear.jpg"))
        XCTAssertGreaterThanOrEqual(p.r, 250)
        XCTAssertGreaterThanOrEqual(p.g, 250)
        XCTAssertGreaterThanOrEqual(p.b, 250)
    }

    func testTheFlatteningStepItselfPutsTransparencyOnWhite() throws {
        // ImageIO's JPEG writer also composites onto white on this system; our own step must not depend on that.
        let flat = try XCTUnwrap(ImageIOEncoder.flattenedOnWhite(try makeImage(alpha: true, fill: (0, 0, 0, 0))))
        XCTAssertEqual(flat.alphaInfo, .noneSkipLast)
        var data = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(flat, in: CGRect(x: 0, y: 0, width: flat.width, height: flat.height))
        XCTAssertEqual(Array(data), [255, 255, 255, 255])
    }

    func testFlatteningKeepsTheOriginalColorSpace() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let flat = try XCTUnwrap(ImageIOEncoder.flattenedOnWhite(try makeImage(colorSpace: p3, alpha: true, fill: (0, 1, 0, 0.5))))
        XCTAssertEqual(flat.colorSpace?.name as String?, CGColorSpace.displayP3 as String)
    }

    func testHalfTransparentRedBecomesLightRedOnWhite() async throws {
        let source = try write(try makeImage(alpha: true, fill: (1, 0, 0, 0.5)), as: .png, named: "half.png")
        _ = await convert([source], to: "jpeg")
        let p = try pixel(dir.appendingPathComponent("half.jpg"))
        XCTAssertGreaterThan(p.r, 240)
        XCTAssertEqual(p.g, 128, accuracy: 12)
        XCTAssertEqual(p.b, 128, accuracy: 12)
    }

    func testAlphaIsKeptWhereTheFormatCanStoreIt() async throws {
        let source = try write(try makeImage(alpha: true, fill: (0, 0, 1, 0.5)), as: .png, named: "blue.png")
        _ = await convert([source], to: "tiff")
        XCTAssertEqual(try pixel(dir.appendingPathComponent("blue.tiff")).a, 128, accuracy: 3)
    }

    // MARK: Names

    func testAnExistingOutputIsNeverOverwritten() async throws {
        let source = try write(try makeImage(), as: .png, named: "a.png")
        let existing = dir.appendingPathComponent("a.jpg")
        try Data("OLD".utf8).write(to: existing)

        let results = await convert([source], to: "jpeg")

        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(output.lastPathComponent, "a 2.jpg")
        XCTAssertEqual(try Data(contentsOf: existing), Data("OLD".utf8))
    }

    func testTwoSourcesWithTheSameNameInOneBatchGetDifferentOutputs() async throws {
        let png = try write(try makeImage(), as: .png, named: "a.png")
        let gif = try write(try makeImage(), as: .gif, named: "a.gif")
        let results = await convert([png, gif], to: "jpeg")
        let outputs = results.compactMap { result -> String? in if case .converted(_, let output, _) = result { return output.lastPathComponent }; return nil }
        XCTAssertEqual(Set(outputs), ["a.jpg", "a 2.jpg"])
        XCTAssertEqual(outputs.count, 2)
    }

    func testAnOutputThatAppearsAtTheLastMomentIsStillNotOverwritten() async throws {
        let source = try write(try makeImage(), as: .png, named: "a.png")
        let existing = dir.appendingPathComponent("a.jpg")
        try Data("OLD".utf8).write(to: existing)
        // The existence check claims the name is free (someone created the file after the check).
        let racing = ImageConverter(encoder: ImageIOEncoder(), fileExists: { _ in false })

        let results = await racing.convert(files: [source], to: format("jpeg"), options: ImageEncodingOptions(), progress: { _, _ in })

        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(output.lastPathComponent, "a 2.jpg")
        XCTAssertEqual(try Data(contentsOf: existing), Data("OLD".utf8))
        XCTAssertEqual(try files(), ["a 2.jpg", "a.jpg", "a.png"])
    }

    // MARK: Detecting by content

    func testTheExtensionIsIgnoredWhenDetectingTheSource() async throws {
        let png = try write(try makeImage(), as: .png, named: "x.png")
        let disguised = dir.appendingPathComponent("photo.dat")
        try FileManager.default.copyItem(at: png, to: disguised)
        let results = await convert([disguised], to: "jpeg")
        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(output.lastPathComponent, "photo.jpg")
    }

    func testAFileAlreadyInTheTargetFormatIsSkippedEvenWithTheWrongExtension() async throws {
        let jpeg = try write(try makeImage(), as: .jpeg, named: "wrong.png")
        let real = try write(try makeImage(), as: .jpeg, named: "real.jpeg")
        let results = await convert([jpeg, real], to: "jpeg")
        XCTAssertEqual(results, [.skipped(source: jpeg, reason: .alreadyInFormat), .skipped(source: real, reason: .alreadyInFormat)])
        XCTAssertEqual(try files(), ["real.jpeg", "wrong.png"], "nothing new is written")
    }

    func testANonImageFails() async throws {
        let text = dir.appendingPathComponent("notes.png")
        try Data("not an image at all".utf8).write(to: text)
        let results = await convert([text], to: "jpeg")
        XCTAssertEqual(results, [.failed(source: text, message: "not an image")])
        XCTAssertEqual(try files(), ["notes.png"])
    }

    func testAMissingFileFailsWithoutCrashing() async {
        let missing = dir.appendingPathComponent("gone.png")
        let results = await convert([missing], to: "jpeg")
        guard case .failed(let source, let message)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(source, missing)
        XCTAssertFalse(message.isEmpty)
    }

    func testOneBadFileDoesNotStopTheRest() async throws {
        let good1 = try write(try makeImage(), as: .png, named: "g1.png")
        let bad = dir.appendingPathComponent("bad.png")
        try Data("nope".utf8).write(to: bad)
        let good2 = try write(try makeImage(), as: .png, named: "g2.png")
        let results = await convert([good1, bad, good2], to: "jpeg")
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(ConversionSummary(results: results, format: format("jpeg")).convertedCount, 2)
        XCTAssertEqual(results[1], .failed(source: bad, message: "not an image"))
    }

    func testResultsStayInTheOrderOfTheInput() async throws {
        let urls = try (1...6).map { try write(try makeImage(), as: .png, named: "f\($0).png") }
        let results = await convert(urls, to: "tiff")
        XCTAssertEqual(results.map { result -> URL? in if case .converted(let source, _, _) = result { return source }; return nil }, urls)
    }

    // MARK: Metadata

    func testExifAndOrientationSurviveAConversion() async throws {
        let source = try write(try makeImage(), as: .jpeg, named: "cam.jpg", properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RoundelCam", kCGImagePropertyTIFFModel: "T1"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Lens 50mm"],
        ])
        XCTAssertEqual((properties(source)[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String] as? String, "RoundelCam", "precondition")

        _ = await convert([source], to: "tiff")

        let out = properties(dir.appendingPathComponent("cam.tiff"))
        XCTAssertEqual(out[kCGImagePropertyOrientation as String] as? Int, 6)
        XCTAssertEqual((out[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String] as? String, "RoundelCam")
        XCTAssertEqual((out[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifLensModel as String] as? String, "Lens 50mm")
    }

    func testFormatsWithoutAnOrientationTagGetTheRotationAppliedToThePixels() async throws {
        // Stored 40x20 with orientation 6 (rotate 90° clockwise): it should display as 20x40.
        let source = try write(try makeImage(width: 40, height: 20), as: .jpeg, named: "rot.jpg", properties: [kCGImagePropertyOrientation: 6])
        _ = await convert([source], to: "gif")
        let gif = properties(dir.appendingPathComponent("rot.gif"))
        XCTAssertEqual(gif[kCGImagePropertyPixelWidth as String] as? Int, 20)
        XCTAssertEqual(gif[kCGImagePropertyPixelHeight as String] as? Int, 40)
        XCTAssertTrue((gif[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1, "no tag is left to rotate it a second time")
    }

    func testFormatsThatKeepTheTagKeepTheStoredPixelsToo() async throws {
        let source = try write(try makeImage(width: 40, height: 20), as: .jpeg, named: "rot2.jpg", properties: [kCGImagePropertyOrientation: 6])
        _ = await convert([source], to: "tiff")
        let tiff = properties(dir.appendingPathComponent("rot2.tiff"))
        XCTAssertEqual(tiff[kCGImagePropertyPixelWidth as String] as? Int, 40)
        XCTAssertEqual(tiff[kCGImagePropertyOrientation as String] as? Int, 6)
    }

    func testTheColorProfileSurvivesAConversion() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try write(try makeImage(colorSpace: p3), as: .png, named: "p3.png")
        XCTAssertEqual(properties(source)[kCGImagePropertyProfileName as String] as? String, "Display P3", "precondition")

        _ = await convert([source], to: "tiff")
        _ = await convert([source], to: "jpeg")

        XCTAssertEqual(properties(dir.appendingPathComponent("p3.tiff"))[kCGImagePropertyProfileName as String] as? String, "Display P3")
        XCTAssertEqual(properties(dir.appendingPathComponent("p3.jpg"))[kCGImagePropertyProfileName as String] as? String, "Display P3")
    }

    func testFlatteningKeepsTheColorProfileToo() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try write(try makeImage(colorSpace: p3, alpha: true, fill: (0, 1, 0, 0.5)), as: .png, named: "p3a.png")
        _ = await convert([source], to: "jpeg")
        XCTAssertEqual(properties(dir.appendingPathComponent("p3a.jpg"))[kCGImagePropertyProfileName as String] as? String, "Display P3")
    }

    // MARK: Quality

    func testLowerQualityMakesASmallerJpeg() async throws {
        let source = try write(try noisyImage(), as: .png, named: "noise.png")
        _ = await convert([source], to: "jpeg", quality: 0.95)
        let high = try Data(contentsOf: dir.appendingPathComponent("noise.jpg")).count
        try FileManager.default.removeItem(at: dir.appendingPathComponent("noise.jpg"))
        _ = await convert([source], to: "jpeg", quality: 0.1)
        let low = try Data(contentsOf: dir.appendingPathComponent("noise.jpg")).count
        XCTAssertLessThan(low, high / 2)
    }

    func testQualityIsIgnoredForLosslessFormats() async throws {
        let source = try write(try makeImage(), as: .jpeg, named: "q.jpg")
        let results = await convert([source], to: "png", quality: 0.1)
        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(detectedType(output), "public.png")
    }

    // MARK: Animation

    func testAnAnimatedGifConvertsTheFirstFrameAndSaysSo() async throws {
        let gif = try writeAnimatedGIF(named: "anim.gif", frames: 3)
        let results = await convert([gif], to: "png")
        guard case .converted(_, let output, let notes)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(notes, [.firstFrameOnly])
        XCTAssertEqual(CGImageSourceCreateWithURL(output as CFURL, nil).map(CGImageSourceGetCount), 1)
    }

    func testAStillGifHasNoNote() async throws {
        let gif = try write(try makeImage(), as: .gif, named: "still.gif")
        let results = await convert([gif], to: "png")
        guard case .converted(_, _, let notes)? = results.first else { return XCTFail("\(results)") }
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: Failure cleanup

    private struct FailingEncoder: ImageEncoder {
        func detectType(of url: URL) -> String? { "public.png" }
        func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
            try Data("partial".utf8).write(to: destination)
            throw ImageConversionError.encodeFailed(format: format.displayName)
        }
    }

    func testAFailedEncodeLeavesNoTemporaryFileBehind() async throws {
        let source = try write(try makeImage(), as: .png, named: "a.png")
        let failing = ImageConverter(encoder: FailingEncoder())
        let results = await failing.convert(files: [source], to: format("jpeg"), options: ImageEncodingOptions(), progress: { _, _ in })
        guard case .failed(_, let message)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(message, "the system couldn’t write JPEG")
        XCTAssertEqual(try files(), ["a.png"])
    }

    // MARK: Batches

    private final class CountingEncoder: ImageEncoder, @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = 0
        private(set) var maxInFlight = 0
        func detectType(of url: URL) -> String? { "public.png" }
        func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
            lock.withLock { inFlight += 1; maxInFlight = max(maxInFlight, inFlight) }
            usleep(40_000)
            try Data("x".utf8).write(to: destination)
            lock.withLock { inFlight -= 1 }
            return EncodeOutcome()
        }
    }

    private func dummyFiles(_ count: Int) throws -> [URL] {
        try (1...count).map { index in
            let url = dir.appendingPathComponent("img\(index).png")
            try Data("png".utf8).write(to: url)
            return url
        }
    }

    func testABatchRunsWithLimitedConcurrency() async throws {
        let encoder = CountingEncoder()
        let limited = ImageConverter(encoder: encoder, maxConcurrent: 3)
        let results = await limited.convert(files: try dummyFiles(10), to: format("jpeg"), options: ImageEncodingOptions(), progress: { _, _ in })
        XCTAssertEqual(results.count, 10)
        XCTAssertLessThanOrEqual(encoder.maxInFlight, 3)
        XCTAssertGreaterThanOrEqual(encoder.maxInFlight, 2, "it does run in parallel")
    }

    func testAConcurrencyOfOneRunsOneAtATime() async throws {
        let encoder = CountingEncoder()
        let serial = ImageConverter(encoder: encoder, maxConcurrent: 1)
        _ = await serial.convert(files: try dummyFiles(4), to: format("jpeg"), options: ImageEncodingOptions(), progress: { _, _ in })
        XCTAssertEqual(encoder.maxInFlight, 1)
    }

    func testProgressCountsEveryFileOnceAndEndsAtTheTotal() async throws {
        let progress = ProgressLog()
        _ = await ImageConverter(encoder: CountingEncoder()).convert(files: try dummyFiles(10), to: format("jpeg"), options: ImageEncodingOptions(), progress: { done, total in
            progress.add(done, total)
        })
        XCTAssertEqual(progress.dones.sorted(), Array(1...10))
        XCTAssertEqual(Set(progress.totals), [10])
    }

    func testProgressIsReportedForSkippedAndFailedFilesToo() async throws {
        let jpeg = try write(try makeImage(), as: .jpeg, named: "s.jpg")
        let text = dir.appendingPathComponent("t.png")
        try Data("x".utf8).write(to: text)
        let png = try write(try makeImage(), as: .png, named: "p.png")
        let progress = ProgressLog()
        _ = await converter.convert(files: [jpeg, text, png], to: format("jpeg"), options: ImageEncodingOptions(), progress: { done, total in progress.add(done, total) })
        XCTAssertEqual(progress.dones.sorted(), [1, 2, 3])
    }

    func testAnEmptyBatchDoesNothing() async {
        let results = await convert([], to: "jpeg")
        XCTAssertEqual(results, [])
    }

    func testHeicIsWrittenWhenTheSystemCan() async throws {
        let heic = format("heic")
        try XCTSkipUnless(SystemImageCapabilities().writableTypeIdentifiers.contains(heic.typeIdentifier), "this system cannot write HEIC")
        let source = try write(try makeImage(), as: .png, named: "h.png")
        let results = await convert([source], to: "heic", quality: 0.8)
        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(detectedType(output), "public.heic")
    }

    func testTheSystemCapabilityListIncludesTheCommonFormats() {
        let writable = Set(SystemImageCapabilities().writableTypeIdentifiers)
        for id in ["public.png", "public.jpeg", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp"] {
            XCTAssertTrue(writable.contains(id), id)
        }
    }

    // MARK: Helpers

    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _dones: [Int] = []
        private var _totals: [Int] = []
        var dones: [Int] { lock.withLock { _dones } }
        var totals: [Int] { lock.withLock { _totals } }
        func add(_ done: Int, _ total: Int) { lock.withLock { _dones.append(done); _totals.append(total) } }
    }
}
