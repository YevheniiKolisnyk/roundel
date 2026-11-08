import XCTest
import ImageIO
import CoreGraphics
import RoundelCore
@testable import RoundelWebP

/// Compressing WebP files with the libwebp backend, end to end, on generated pictures in a temporary directory.
final class WebPCompressionTests: XCTestCase {
    private var dir: URL!
    private let backends = ImageBackends([ImageIOEncoder(), WebPEncoder()])
    private var webp: ImageFormat { ImageFormats.format(forKey: "webp")! }
    private var compressor: ImageCompressor { ImageCompressor(encoder: backends) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-webp-compress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    // MARK: Pictures

    private func picture(width: Int = 400, height: Int = 300) throws -> CGImage {
        var state: UInt32 = 21
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 1_664_525 &+ 1_013_904_223
                let n = Int(state >> 28) - 8
                let fx = Double(x) / Double(width), fy = Double(y) / Double(height)
                let r = 120 + 90 * sin(fx * 5 + fy * 2), g = 130 + 80 * cos(fx * 3 - fy * 4), b = 140 + 70 * sin(fx * 2 + fy * 6)
                let i = (y * width + x) * 4
                bytes[i] = UInt8(max(0, min(255, Int(r) + n))); bytes[i + 1] = UInt8(max(0, min(255, Int(g) + n))); bytes[i + 2] = UInt8(max(0, min(255, Int(b) + n)))
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func writePNG(_ image: CGImage, _ name: String, properties: [CFString: Any] = [:]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    private func makeWebP(from png: URL, named name: String, quality: Double, lossless: Bool, thorough: Bool = false) throws -> URL {
        let url = dir.appendingPathComponent(name)
        _ = try WebPEncoder().encode(source: png, to: url, format: webp, options: ImageEncodingOptions(quality: quality, lossless: lossless, thorough: thorough))
        return url
    }

    private func pixels(_ url: URL) throws -> [UInt8] {
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &out, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return out
    }

    private func chunkNames(_ url: URL) throws -> [String] {
        let bytes = [UInt8](try Data(contentsOf: url))
        var names: [String] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            names.append(String(decoding: bytes[offset..<offset + 4], as: UTF8.self))
            let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
            offset += 8 + size + size % 2
        }
        return names
    }

    // MARK: Tests

    func testALossyWebPIsRecompressedLossyAndStaysSimilar() async throws {
        let png = try writePNG(try picture(), "src.png")
        let source = try makeWebP(from: png, named: "photo.webp", quality: 0.95, lossless: false)
        XCTAssertEqual(WebPContainer.kind(of: try Data(contentsOf: source)), .lossy)
        let results = await compressor.compress(files: [source], options: CompressionOptions(preset: .balanced), progress: { _, _ in })
        guard case .compressed(_, let output, let before, let after)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(output.lastPathComponent, "photo compressed.webp")
        XCTAssertLessThan(after, before)
        XCTAssertEqual(WebPContainer.kind(of: try Data(contentsOf: output)), .lossy)
        // Similar: mean absolute difference of the pixels is small.
        let a = try pixels(source), b = try pixels(output)
        let mad = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        XCTAssertLessThan(Double(mad) / Double(a.count), 6, "mean absolute difference per byte")
    }

    func testALosslessWebPStaysLosslessWithTheSamePixels() async throws {
        let png = try writePNG(try picture(width: 240, height: 180), "src.png")
        let source = try makeWebP(from: png, named: "exact.webp", quality: 0.0, lossless: true)   // quick and bigger
        XCTAssertEqual(WebPContainer.kind(of: try Data(contentsOf: source)), .lossless)
        let results = await compressor.compress(files: [source], options: CompressionOptions(preset: .strong), progress: { _, _ in })
        switch results.first {
        case .compressed(_, let output, let before, let after)?:
            XCTAssertLessThan(after, before)
            XCTAssertEqual(WebPContainer.kind(of: try Data(contentsOf: output)), .lossless, "never silently becomes lossy")
            XCTAssertEqual(try pixels(output), try pixels(source), "the same pixels")
        case .alreadyOptimal?:
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("compressed") }, [], "nothing written")
        default:
            XCTFail("\(String(describing: results.first))")
        }
    }

    func testTheThoroughSettingsMakeASmallerOrEqualFile() throws {
        let png = try writePNG(try picture(), "src.png")
        for lossless in [false, true] {
            let normal = try makeWebP(from: png, named: "n\(lossless).webp", quality: lossless ? 0.5 : 0.7, lossless: lossless)
            let thorough = try makeWebP(from: png, named: "t\(lossless).webp", quality: lossless ? 0.5 : 0.7, lossless: lossless, thorough: true)
            let a = try Data(contentsOf: normal).count, b = try Data(contentsOf: thorough).count
            XCTAssertLessThanOrEqual(b, a + a / 100, "lossless \(lossless): \(b) vs \(a)")
        }
    }

    func testMaxDimensionAndStripMetadataApplyToWebPToo() async throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 50.45, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 30.52, kCGImagePropertyGPSLongitudeRef: "E"]
        let jpeg = dir.appendingPathComponent("geo.jpg")
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(jpeg as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, try picture(), [kCGImagePropertyGPSDictionary: gps, kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let source = dir.appendingPathComponent("geo.webp")
        _ = try WebPEncoder().encode(source: jpeg, to: source, format: webp, options: ImageEncodingOptions(quality: 0.95))
        XCTAssertTrue(try chunkNames(source).contains("EXIF"), "precondition: the source carries EXIF")

        let kept = await compressor.compress(files: [source], options: CompressionOptions(preset: .balanced, maxDimension: 200), progress: { _, _ in })
        guard case .compressed(_, let keptOutput, _, _)? = kept.first else { return XCTFail("\(kept)") }
        XCTAssertTrue(try chunkNames(keptOutput).contains("EXIF"), "kept by default")
        let size = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(try XCTUnwrap(CGImageSourceCreateWithURL(keptOutput as CFURL, nil)), 0, nil) as? [CFString: Any])
        XCTAssertEqual(size[kCGImagePropertyPixelWidth] as? Int, 200)

        try FileManager.default.removeItem(at: keptOutput)
        let stripped = await compressor.compress(files: [source], options: CompressionOptions(preset: .balanced, stripMetadata: true), progress: { _, _ in })
        guard case .compressed(_, let strippedOutput, _, _)? = stripped.first else { return XCTFail("\(stripped)") }
        XCTAssertFalse(try chunkNames(strippedOutput).contains("EXIF"), "stripped on request")
    }

    func testAWebPWithAnUnreadableContainerIsNotTouched() async throws {
        let url = dir.appendingPathComponent("junk.webp")
        try Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPnothing".utf8).write(to: url)
        let results = await compressor.compress(files: [url], options: CompressionOptions(), progress: { _, _ in })
        guard case .failed? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["junk.webp"])
    }
}
