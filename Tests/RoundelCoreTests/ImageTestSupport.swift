import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import RoundelCore

/// Generated pictures and a similarity metric for tests. Nothing here touches anything outside the temporary directories
/// the tests make.
enum TestImages {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A picture that looks like a photograph to a compressor: smooth tones, a few edges, a little grain. Deterministic.
    static func photo(width: Int = 320, height: Int = 240, grain: Int = 2, seed: UInt32 = 11) -> CGImage {
        var noise = TestNoise(state: seed)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let fx = Double(x) / Double(width), fy = Double(y) / Double(height)
                var r = 120 + 90 * sin(fx * 5.0 + fy * 2.0) + 30 * sin(fy * 17.0)
                var g = 130 + 80 * cos(fx * 3.0 - fy * 4.0) + 25 * sin(fx * 21.0)
                var b = 140 + 70 * sin(fx * 2.0 + fy * 6.0) + 20 * cos(fx * 13.0 + fy * 9.0)
                let dx = fx - 0.65, dy = fy - 0.4
                if dx * dx + dy * dy < 0.04 { r = 220 - 60 * fx; g = 90 + 40 * fy; b = 70 }   // a disc with a hard edge
                if abs(fy - 0.8) < 0.012 { r = 20; g = 20; b = 25 }                              // a thin line
                let n = grain == 0 ? 0 : (noise.next() % (2 * grain + 1)) - grain
                let i = (y * width + x) * 4
                bytes[i] = UInt8(max(0, min(255, Int(r) + n)))
                bytes[i + 1] = UInt8(max(0, min(255, Int(g) + n)))
                bytes[i + 2] = UInt8(max(0, min(255, Int(b) + n)))
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    @discardableResult
    static func write(_ image: CGImage, as type: String, to url: URL, quality: Double? = nil, properties: [CFString: Any] = [:]) throws -> URL {
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        var options = properties
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(sink, image, options as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink), "writing \(url.lastPathComponent)")
        return url
    }

    /// A PNG file's bytes for `image` (as ImageIO writes it).
    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return data as Data
    }

    static func load(_ url: URL) throws -> CGImage {
        try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }, "reading \(url.lastPathComponent)")
    }

    static func properties(of url: URL) -> [CFString: Any] {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    }

    /// 8-bit RGBA in sRGB, row by row, whatever the image's own format.
    static func rgba(_ image: CGImage, width: Int? = nil, height: Int? = nil) -> [UInt8] {
        let w = width ?? image.width, h = height ?? image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out
    }

    // MARK: Similarity

    private static func luma(_ rgba: [UInt8]) -> [Double] {
        stride(from: 0, to: rgba.count, by: 4).map { 0.299 * Double(rgba[$0]) + 0.587 * Double(rgba[$0 + 1]) + 0.114 * Double(rgba[$0 + 2]) }
    }

    /// Mean structural similarity of the luminance over 8x8 windows (stride 4): 1 is identical.
    static func ssim(_ a: CGImage, _ b: CGImage) -> Double {
        let w = min(a.width, b.width), h = min(a.height, b.height)
        let x = luma(rgba(a, width: w, height: h)), y = luma(rgba(b, width: w, height: h))
        let c1: Double = 6.5025, c2: Double = 58.5225   // (0.01 * 255)^2 and (0.03 * 255)^2
        var total = 0.0
        var windows = 0
        for oy in stride(from: 0, to: h - 8, by: 4) {
            for ox in stride(from: 0, to: w - 8, by: 4) {
                var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
                for j in 0..<8 {
                    for i in 0..<8 {
                        let p = x[(oy + j) * w + ox + i], q = y[(oy + j) * w + ox + i]
                        sx += p; sy += q; sxx += p * p; syy += q * q; sxy += p * q
                    }
                }
                let mx = sx / 64, my = sy / 64
                let vx = sxx / 64 - mx * mx, vy = syy / 64 - my * my, cov = sxy / 64 - mx * my
                total += ((2 * mx * my + c1) * (2 * cov + c2)) / ((mx * mx + my * my + c1) * (vx + vy + c2))
                windows += 1
            }
        }
        return windows == 0 ? 1 : total / Double(windows)
    }

    static func psnr(_ a: CGImage, _ b: CGImage) -> Double {
        let w = min(a.width, b.width), h = min(a.height, b.height)
        let x = rgba(a, width: w, height: h), y = rgba(b, width: w, height: h)
        var sum = 0.0
        for i in stride(from: 0, to: x.count, by: 4) { for k in 0..<3 { let d = Double(x[i + k]) - Double(y[i + k]); sum += d * d } }
        let mse = sum / Double(w * h * 3)
        let peak: Double = 255.0 * 255.0
        return mse == 0 ? 99 : 10 * log10(peak / mse)
    }
}

/// A temporary directory per test, removed afterwards.
class TempDirTestCase: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-compress-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    func listing() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }
    func size(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0 }
}
