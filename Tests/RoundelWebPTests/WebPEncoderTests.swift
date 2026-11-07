import XCTest
import ImageIO
import UniformTypeIdentifiers
import RoundelCore
@testable import RoundelWebP

/// The libwebp backend, end to end: encode with libwebp, read back with ImageIO. Generated images and a temporary
/// directory only.
final class WebPEncoderTests: XCTestCase {
    private var dir: URL!
    private let backends = ImageBackends([ImageIOEncoder(), WebPEncoder()])
    private var converter: ImageConverter { ImageConverter(encoder: backends) }
    private var webp: ImageFormat { ImageFormats.format(forKey: "webp")! }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-webp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Generated images

    private func makeImage(width: Int = 32, height: Int = 24, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!, alpha: Bool = false,
                           fill: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0.9, 0.2, 0.1, 1)) throws -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: info))
        context.setFillColor(red: fill.r, green: fill.g, blue: fill.b, alpha: fill.a)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func noisyImage(side: Int = 64) throws -> CGImage {
        var state: UInt32 = 987_654
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<bytes.count {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes[i] = i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 24)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @discardableResult
    private func write(_ image: CGImage, as type: UTType, named name: String, properties: [CFString: Any] = [:]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func convert(_ url: URL, quality: Double? = nil, lossless: Bool = false) async throws -> (output: URL, notes: [ConversionNote]) {
        let results = await converter.convert(files: [url], to: webp, options: ImageEncodingOptions(quality: quality, lossless: lossless), progress: { _, _ in })
        guard case .converted(_, let output, let notes)? = results.first else {
            XCTFail("not converted: \(results)")
            throw ConversionDidNotSucceed()
        }
        return (output, notes)
    }

    private struct ConversionDidNotSucceed: Error {}

    // MARK: Reading back

    private func properties(_ url: URL) -> [String: Any] {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
    }

    /// Premultiplied RGBA of the whole image, read by ImageIO.
    private func pixels(_ url: URL) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (image.width, image.height, data)
    }

    /// The RIFF chunks of a WebP file: four-character code and payload.
    private func chunks(_ url: URL) throws -> [(code: String, payload: Data)] {
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WEBP")
        var result: [(String, Data)] = []
        var offset = 12
        while offset + 8 <= data.count {
            let code = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(data[offset + 4]) | Int(data[offset + 5]) << 8 | Int(data[offset + 6]) << 16 | Int(data[offset + 7]) << 24
            let end = min(offset + 8 + size, data.count)
            result.append((code, Data(data[offset + 8..<end])))
            offset += 8 + size + (size & 1)
        }
        return result
    }

    private func chunk(_ code: String, in url: URL) throws -> Data? {
        try chunks(url).first { $0.code == code }?.payload
    }

    // MARK: The backend

    func testTheBackendWritesWebpAndNothingElse() {
        let backend = WebPEncoder()
        XCTAssertEqual(backend.name, "libwebp")
        XCTAssertEqual(backend.writableTypeIdentifiers, ["org.webmproject.webp"])
    }

    func testTheBackendNeverReadsAnything() throws {
        // Reading WebP is ImageIO's job, so libwebp's decoder is never involved.
        let png = try write(try makeImage(), as: .png, named: "a.png")
        XCTAssertNil(WebPEncoder().detectType(of: png))
        let webpFile = try convertSync(png)
        XCTAssertNil(WebPEncoder().detectType(of: webpFile), "not even its own output")
    }

    private func convertSync(_ png: URL) throws -> URL {
        let out = dir.appendingPathComponent("sync-\(UUID().uuidString).webp")
        _ = try WebPEncoder().encode(source: png, to: out, format: webp, options: ImageEncodingOptions())
        return out
    }

    func testImageIOReadsTheWebpWeWrite() async throws {
        let source = try write(try makeImage(width: 40, height: 17), as: .png, named: "a.png")
        let (output, _) = try await convert(source)
        XCTAssertEqual(ImageIOEncoder().detectType(of: output), "org.webmproject.webp", "detected by content")
        XCTAssertEqual(properties(output)[kCGImagePropertyPixelWidth as String] as? Int, 40)
        XCTAssertEqual(properties(output)[kCGImagePropertyPixelHeight as String] as? Int, 17)
    }

    func testTheMergedBackendsOfferWebpAndSendEachFormatToTheRightEncoder() {
        XCTAssertTrue(backends.writableTypeIdentifiers.contains("org.webmproject.webp"))
        XCTAssertTrue(ImageFormats.available(writable: backends.writableTypeIdentifiers).contains { $0.key == "webp" })
        XCTAssertEqual(backends.backend(for: ImageFormats.format(forKey: "png")!)?.name, "ImageIO")
        let imageIOWritesWebp = ImageIOEncoder().writableTypeIdentifiers.contains("org.webmproject.webp")
        XCTAssertEqual(backends.backend(for: webp)?.name, imageIOWritesWebp ? "ImageIO" : "libwebp", "ImageIO keeps priority")
    }

    func testTheGeneratedConvertGroupGetsWebp() {
        let group = GroupNode(id: "c", title: "Convert", children: [], generate: "image.convert.formats", params: .object(["quality": .number(0.7), "lossless": .bool(false)]))
        let nodes = ImageConvertFormatsGenerator(capabilities: backends).children(for: group)
        XCTAssertTrue(nodes.contains { $0.id == "c.webp" })
    }

    // MARK: Names and skipping

    func testTheOutputIsNamedWithWebpNextToTheSource() async throws {
        let source = try write(try makeImage(), as: .png, named: "photo.png")
        let (output, _) = try await convert(source)
        XCTAssertEqual(output, dir.appendingPathComponent("photo.webp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the original stays")
    }

    func testAnExistingWebpIsNotOverwritten() async throws {
        let source = try write(try makeImage(), as: .png, named: "photo.png")
        let existing = dir.appendingPathComponent("photo.webp")
        try Data("OLD".utf8).write(to: existing)
        let (output, _) = try await convert(source)
        XCTAssertEqual(output.lastPathComponent, "photo 2.webp")
        XCTAssertEqual(try Data(contentsOf: existing), Data("OLD".utf8))
    }

    func testAFileThatIsAlreadyWebpIsSkippedWhateverItIsCalled() async throws {
        let source = try write(try makeImage(), as: .png, named: "photo.png")
        let (output, _) = try await convert(source)
        let renamed = dir.appendingPathComponent("looks-like.png")
        try FileManager.default.moveItem(at: output, to: renamed)
        let results = await converter.convert(files: [renamed], to: webp, options: ImageEncodingOptions(), progress: { _, _ in })
        XCTAssertEqual(results, [.skipped(source: renamed, reason: .alreadyInFormat)])
    }

    func testWebpCanBeConvertedBackToPng() async throws {
        let source = try write(try makeImage(), as: .png, named: "photo.png")
        let (output, _) = try await convert(source)
        let results = await converter.convert(files: [output], to: ImageFormats.format(forKey: "png")!, options: ImageEncodingOptions(), progress: { _, _ in })
        guard case .converted(_, let png, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(ImageIOEncoder().detectType(of: png), "public.png")
    }

    // MARK: Lossy and lossless

    func testLosslessIsPixelExactAndLossyIsNot() async throws {
        let source = try write(try noisyImage(), as: .png, named: "noise.png")
        let original = try pixels(source)

        let (lossless, _) = try await convert(source, lossless: true)
        XCTAssertEqual(try pixels(lossless).rgba, original.rgba)
        let losslessBytes = try Data(contentsOf: lossless).count

        try FileManager.default.removeItem(at: lossless)   // the lossy file gets the same name
        let (lossy, _) = try await convert(source, quality: 0.3)
        XCTAssertNotEqual(try pixels(lossy).rgba, original.rgba)
        XCTAssertLessThan(try Data(contentsOf: lossy).count, losslessBytes)
    }

    func testLossyQualityChangesTheFileSize() async throws {
        let source = try write(try noisyImage(), as: .png, named: "noise.png")
        let (high, _) = try await convert(source, quality: 0.95)
        let highBytes = try Data(contentsOf: high).count
        try FileManager.default.removeItem(at: high)
        let (low, _) = try await convert(source, quality: 0.1)
        XCTAssertLessThan(try Data(contentsOf: low).count, highBytes / 2)
    }

    func testTheLosslessEffortOnlyChangesTheEffort() async throws {
        let source = try write(try noisyImage(side: 48), as: .png, named: "n.png")
        let original = try pixels(source)
        for effort in [0.0, 1.0] {
            let (output, _) = try await convert(source, quality: effort, lossless: true)
            XCTAssertEqual(try pixels(output).rgba, original.rgba, "effort \(effort)")
            try FileManager.default.removeItem(at: output)
        }
    }

    func testLosslessAndLossyUseTheRightBitstream() async throws {
        let source = try write(try makeImage(), as: .png, named: "a.png")
        let (lossy, _) = try await convert(source)
        XCTAssertTrue(try chunks(lossy).contains { $0.code == "VP8 " })
        try FileManager.default.removeItem(at: lossy)
        let (lossless, _) = try await convert(source, lossless: true)
        XCTAssertTrue(try chunks(lossless).contains { $0.code == "VP8L" })
    }

    // MARK: Alpha

    func testAlphaSurvivesLossless() async throws {
        let half = try write(try makeImage(alpha: true, fill: (1, 0, 0, 0.5)), as: .png, named: "half.png")
        let clear = try write(try makeImage(alpha: true, fill: (0, 0, 0, 0)), as: .png, named: "clear.png")
        let (halfOut, _) = try await convert(half, lossless: true)
        let (clearOut, _) = try await convert(clear, lossless: true)
        let h = try pixels(halfOut).rgba
        XCTAssertEqual(Int(h[3]), 128, accuracy: 2, "alpha")
        XCTAssertEqual(Int(h[0]), 128, accuracy: 3, "premultiplied red of a half-transparent red")
        XCTAssertEqual(try pixels(clearOut).rgba[3], 0)
    }

    func testAlphaSurvivesLossy() async throws {
        let half = try write(try makeImage(alpha: true, fill: (0, 0, 1, 0.5)), as: .png, named: "half.png")
        let (output, _) = try await convert(half, quality: 0.8)
        XCTAssertEqual(Int(try pixels(output).rgba[3]), 128, accuracy: 3)
    }

    func testOpaqueImagesStayOpaque() async throws {
        let source = try write(try makeImage(), as: .png, named: "solid.png")
        let (output, _) = try await convert(source)
        XCTAssertEqual(try pixels(output).rgba[3], 255)
    }

    // MARK: Color profile

    func testAWideGamutProfileIsEmbeddedAndReadBack() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try write(try makeImage(colorSpace: p3), as: .png, named: "p3.png")
        let (output, _) = try await convert(source)
        let profile = try XCTUnwrap(try chunk("ICCP", in: output))
        XCTAssertEqual(String(decoding: profile[36..<40], as: UTF8.self), "acsp")
        XCTAssertEqual(properties(output)[kCGImagePropertyProfileName as String] as? String, "Display P3")
    }

    func testSrgbGetsNoProfileChunk() async throws {
        let source = try write(try makeImage(), as: .png, named: "s.png")
        let (output, _) = try await convert(source)
        XCTAssertNil(try chunk("ICCP", in: output), "no profile means sRGB for WebP")
    }

    func testTheProfileFlagIsSetInTheHeader() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try write(try makeImage(colorSpace: p3), as: .png, named: "p3.png")
        let (output, _) = try await convert(source)
        let header = try XCTUnwrap(try chunk("VP8X", in: output))
        XCTAssertNotEqual(header[0] & 0x20, 0, "ICC profile flag")
    }

    func testAGrayImageConverts() async throws {
        let gray = CGColorSpaceCreateDeviceGray()
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let source = try write(try XCTUnwrap(context.makeImage()), as: .png, named: "gray.png")
        let (output, notes) = try await convert(source)
        XCTAssertEqual(ImageIOEncoder().detectType(of: output), "org.webmproject.webp")
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: EXIF and orientation

    private let exifProperties: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RoundelCam", kCGImagePropertyTIFFModel: "T1"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Lens 50mm"],
    ]

    func testExifIsCarriedInTheExifChunkAndReadBack() async throws {
        let source = try write(try makeImage(), as: .jpeg, named: "cam.jpg", properties: exifProperties)
        let (output, _) = try await convert(source)
        let blob = try XCTUnwrap(try chunk("EXIF", in: output))
        XCTAssertNotNil(blob.range(of: Data("RoundelCam".utf8)))
        let tiff = properties(output)[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake as String] as? String, "RoundelCam", "ImageIO reads the EXIF chunk back")
        let exif = properties(output)[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifLensModel as String] as? String, "Lens 50mm")
        XCTAssertEqual(exif?[kCGImagePropertyExifPixelXDimension as String] as? Int, 32, "the real size, not a placeholder")
        XCTAssertEqual(exif?[kCGImagePropertyExifPixelYDimension as String] as? Int, 24)
    }

    func testAnImageWithoutExifGetsNoExifChunk() async throws {
        let source = try write(try makeImage(), as: .png, named: "plain.png")
        let (output, _) = try await convert(source)
        XCTAssertNil(try chunk("EXIF", in: output))
    }

    func testOrientationIsAppliedToThePixelsNotKeptAsATag() async throws {
        var properties = exifProperties
        properties[kCGImagePropertyOrientation] = 6
        let source = try write(try makeImage(width: 40, height: 20), as: .jpeg, named: "rot.jpg", properties: properties)
        let (output, _) = try await convert(source)
        XCTAssertEqual(self.properties(output)[kCGImagePropertyPixelWidth as String] as? Int, 20)
        XCTAssertEqual(self.properties(output)[kCGImagePropertyPixelHeight as String] as? Int, 40)
        XCTAssertTrue((self.properties(output)[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1, "no tag left to rotate it twice")
        XCTAssertNotNil(try chunk("EXIF", in: output), "the rest of the EXIF is still there")
    }

    // MARK: What is lost

    func testIptcAndResolutionAreReportedAsNotKept() async throws {
        let source = try write(try makeImage(), as: .jpeg, named: "news.jpg", properties: [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["roundel"]],
            kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300,
        ])
        let (_, notes) = try await convert(source)
        XCTAssertEqual(notes, [.metadataNotKept(["IPTC", "resolution"])])
    }

    func testNothingIsReportedWhenNothingWasLost() async throws {
        let source = try write(try makeImage(), as: .png, named: "p.png")
        let (_, notes) = try await convert(source)
        XCTAssertEqual(notes, [])
    }

    // MARK: Animation

    func testAnAnimatedGifConvertsTheFirstFrameAndSaysSo() async throws {
        let url = dir.appendingPathComponent("anim.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil))
        for i in 0..<3 { CGImageDestinationAddImage(destination, try makeImage(fill: (CGFloat(i) / 3, 0.5, 0.5, 1)), nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let (output, notes) = try await convert(url)
        XCTAssertEqual(notes, [.firstFrameOnly])
        XCTAssertEqual(CGImageSourceCreateWithURL(output as CFURL, nil).map(CGImageSourceGetCount), 1)
    }

    // MARK: Limits and failures

    func testTheLargestSideWebpAllowsIsAccepted() async throws {
        let source = try write(try makeImage(width: 16383, height: 1), as: .png, named: "wide.png")
        let (output, _) = try await convert(source)
        XCTAssertEqual(properties(output)[kCGImagePropertyPixelWidth as String] as? Int, 16383)
    }

    func testAnImageTooLargeForWebpFailsWithAClearMessageAndLeavesNothingBehind() async throws {
        let source = try write(try makeImage(width: 16384, height: 1), as: .png, named: "toowide.png")
        let results = await converter.convert(files: [source], to: webp, options: ImageEncodingOptions(), progress: { _, _ in })
        XCTAssertEqual(results, [.failed(source: source, message: "too large for WebP (max 16383 pixels per side)")])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["toowide.png"])
    }

    func testANonImageStillFailsTheSameWay() async throws {
        let text = dir.appendingPathComponent("t.png")
        try Data("nope".utf8).write(to: text)
        let results = await converter.convert(files: [text], to: webp, options: ImageEncodingOptions(), progress: { _, _ in })
        XCTAssertEqual(results, [.failed(source: text, message: "not an image")])
    }
}
