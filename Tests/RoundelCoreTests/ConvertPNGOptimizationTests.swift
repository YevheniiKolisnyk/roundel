import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

/// Convert -> PNG used to produce bloated files (ImageIO's PNG writer is poor). The optimizer now runs on what ImageIO wrote.
final class ConvertPNGOptimizationTests: TempDirTestCase {
    private var png: ImageFormat { ImageFormats.format(forKey: "png")! }
    private let plain = ImageIOEncoder(pngOptimizer: nil)
    private let optimizing = ImageIOEncoder()

    // MARK: Sources

    private func screenshot() -> CGImage {
        let w = 640, h = 400
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: TestImages.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(red: 0.9, green: 0.9, blue: 0.93, alpha: 1); context.fill(CGRect(x: 0, y: h - 40, width: w, height: 40))
        context.setFillColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)
        for i in 0..<30 { context.fill(CGRect(x: 40, y: 330 - i * 10, width: 80 + (i * 37) % 300, height: 5)) }
        context.setFillColor(red: 1, green: 0.37, blue: 0.34, alpha: 1); context.fillEllipse(in: CGRect(x: 480, y: 220, width: 100, height: 100))
        return context.makeImage()!
    }

    private func icon() -> CGImage {
        let s = 256
        let context = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: TestImages.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), CGColor(red: 0.1, green: 0.8, blue: 0.5, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: TestImages.srgb, colors: colors, locations: [0, 1])!
        context.addEllipse(in: CGRect(x: 16, y: 16, width: 224, height: 224)); context.clip()
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: s, y: s), options: [])
        return context.makeImage()!
    }

    private func sources() throws -> [(name: String, url: URL)] {
        [("photo.jpg", try TestImages.write(TestImages.photo(width: 320, height: 240), as: "public.jpeg", to: dir.appendingPathComponent("photo.jpg"), quality: 0.9)),
         ("screenshot.png", try TestImages.write(screenshot(), as: "public.png", to: dir.appendingPathComponent("screenshot.png"))),
         ("icon.png", try TestImages.write(icon(), as: "public.png", to: dir.appendingPathComponent("icon.png"))),
         ("shot.tiff", try TestImages.write(screenshot(), as: "public.tiff", to: dir.appendingPathComponent("shot.tiff")))]
    }

    private func convert(_ encoder: ImageIOEncoder, _ source: URL, to name: String) throws -> URL {
        let out = dir.appendingPathComponent(name)
        _ = try encoder.encode(source: source, to: out, format: png, options: ImageEncodingOptions())
        return out
    }

    // MARK: Tests

    func testTheOptimizedPNGIsTheSamePictureAndNeverBigger() throws {
        for (name, source) in try sources() {
            let a = try convert(plain, source, to: "plain-\(name).png"), b = try convert(optimizing, source, to: "opt-\(name).png")
            let x = try XCTUnwrap(TestPNG.decode(try Data(contentsOf: a)), name), y = try XCTUnwrap(TestPNG.decode(try Data(contentsOf: b)), name)
            XCTAssertEqual(x.width, y.width, name)
            XCTAssertTrue(x.rgba16 == y.rgba16, "\(name): pixels are identical")
            XCTAssertEqual(TestImages.rgba(try TestImages.load(a)), TestImages.rgba(try TestImages.load(b)), "\(name): ImageIO sees the same picture")
            XCTAssertLessThanOrEqual(size(b), size(a), name)
            print("SAMPLE \(name): ImageIO PNG \(size(a)) bytes -> optimized \(size(b)) bytes (\(100 - size(b) * 100 / max(1, size(a)))% smaller)")
        }
    }

    func testFlatPicturesShrinkALot() throws {
        let shot = dir.appendingPathComponent("s.png")
        try TestImages.write(screenshot(), as: "public.png", to: shot)
        let a = try convert(plain, shot, to: "a.png"), b = try convert(optimizing, shot, to: "b.png")
        XCTAssertLessThan(Double(size(b)), Double(size(a)) * 0.7, "\(size(a)) -> \(size(b))")
    }

    func testAnOptimizerThatFailsNeverFailsTheConversion() throws {
        struct Boom: Error {}
        let broken = ImageIOEncoder(pngOptimizer: { _ in throw Boom() })
        let source = try TestImages.write(screenshot(), as: "public.png", to: dir.appendingPathComponent("s.png"))
        let out = try convert(broken, source, to: "o.png")
        XCTAssertEqual(try Data(contentsOf: out), try Data(contentsOf: try convert(plain, source, to: "p.png")), "ImageIO's own file stays")
    }

    func testAnOptimizedResultThatIsNotSmallerIsNotUsed() throws {
        let bigger = ImageIOEncoder(pngOptimizer: { $0 + Data(repeating: 0, count: 100) })
        let source = try TestImages.write(screenshot(), as: "public.png", to: dir.appendingPathComponent("s.png"))
        let out = try convert(bigger, source, to: "o.png")
        XCTAssertEqual(try Data(contentsOf: out), try Data(contentsOf: try convert(plain, source, to: "p.png")))
    }

    func testOnlyPNGOutputIsOptimized() throws {
        var calls = 0
        let counting = ImageIOEncoder(pngOptimizer: { calls += 1; return $0 })
        let source = try TestImages.write(TestImages.photo(width: 64, height: 48), as: "public.png", to: dir.appendingPathComponent("s.png"))
        for key in ["jpeg", "tiff", "gif"] {
            _ = try counting.encode(source: source, to: dir.appendingPathComponent("o.\(key)"), format: ImageFormats.format(forKey: key)!, options: ImageEncodingOptions())
        }
        XCTAssertEqual(calls, 0)
    }

    func testTheEndToEndConversionLeavesNoTemporaryFile() async throws {
        let source = try TestImages.write(TestImages.photo(width: 200, height: 150), as: "public.jpeg", to: dir.appendingPathComponent("p.jpg"), quality: 0.9)
        let results = await ImageConverter(encoder: optimizing).convert(files: [source], to: png, options: ImageEncodingOptions(), progress: { _, _ in })
        guard case .converted(_, let output, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(output.lastPathComponent, "p.png")
        XCTAssertEqual(listing(), ["p.jpg", "p.png"])
        XCTAssertNotNil(try? TestImages.load(output))
    }
}
