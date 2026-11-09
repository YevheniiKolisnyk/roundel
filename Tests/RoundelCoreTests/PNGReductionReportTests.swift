import XCTest
import CoreGraphics
@testable import RoundelCore

/// Not a test of behavior: when ROUNDEL_PNG_REPORT_DIR names a directory, it writes sample pictures (original, lossless result,
/// reduced result) and prints the measurements, for judging the guards' numbers by eye. Does nothing otherwise.
final class PNGReductionReportTests: XCTestCase {
    private func samples() -> [(name: String, png: Data, note: String)] {
        var out: [(String, Data, String)] = []
        // 1. Flat UI with sub-pixel text.
        var noise = TestNoise(state: 17)
        var fringe: [Int: [Int]] = [:]
        func edge(_ key: Int) -> [Int] {
            if let c = fringe[key] { return c }
            let t = (0..<3).map { _ in (noise.next() % 11) * 10 }
            let c = (0..<3).map { 246 - (246 - 40) * t[$0] / 100 }
            fringe[key] = c
            return c
        }
        out.append(("ui", TestPNG.make(.init(width: 640, height: 400, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            var px: [Int] = [246, 246, 248, 255]
            if y < 40 { px = [226, 226, 230, 255] }
            if x < 120 && y >= 40 { px = [236, 236, 241, 255] }
            if x >= 150 && x < 600 && (y % 16) < 11 && y > 60 {
                let k = (x * 31 + (y / 16) * 17) % 7
                px = k < 4 ? [40, 40, 46, 255] : (k < 6 ? edge(x * 1000 + y) + [255] : [246, 246, 248, 255])
            }
            if x > 520 && y < 36 && x < 600 && y > 8 { px = [255, 95, 87, 255] }
            return px[c]
        })), "flat UI with sub-pixel text"))
        // 2. An icon: a disc with a gradient, a soft shadow and transparency.
        out.append(("icon", TestPNG.make(.init(width: 256, height: 256, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            let dx = Double(x) - 128, dy = Double(y) - 118, r = (dx * dx + dy * dy).squareRoot()
            let sdx = Double(x) - 128, sdy = Double(y) - 140, sr = (sdx * sdx + sdy * sdy).squareRoot()
            var px: [Double] = [0, 0, 0, max(0, 70 - sr * 0.45)]                       // soft shadow
            if r < 96 { let t = r / 96; px = [40 + 180 * (1 - t), 120 + 80 * (1 - t), 230 - 60 * t, 255] }
            if r >= 96 && r < 98 { let a = (98 - r) / 2; px = [40, 120, 230, 255 * a] }
            return Int(px[c])
        })), "icon: gradient disc, soft shadow, alpha"))
        // 3. A photograph.
        out.append(("photo", try! TestImages.pngData(TestImages.photo(width: 480, height: 320, grain: 3)), "photograph (grain)"))
        // 4. A smooth gradient banner.
        out.append(("gradient", TestPNG.make(.init(width: 640, height: 160, colorType: 2, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            [60 + x * 150 / 640, 90 + (y / 40) * 3 + x * 30 / 640, 200 - x * 120 / 640][c] })), "smooth gradient (about 2,500 colors)"))
        // 5. A diagram: few flat colors with anti-aliased lines (under 256 colors: the lossless palette already does it).
        out.append(("diagram", TestPNG.make(.init(width: 480, height: 320, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            let line = abs((x * 2 + y) % 90 - 45)
            var px: [Int] = [255, 255, 255, 255]
            if line < 3 { let t = line * 80; px = [80 + t / 2, 120 + t / 3, 200, 255] }
            if (x / 60 + y / 60) % 3 == 0 { px = [235, 240, 250, 255] }
            return px[c]
        })), "diagram: flat fills, anti-aliased lines"))
        return out
    }

    func testWriteTheReportWhenAskedTo() throws {
        guard let dirPath = ProcessInfo.processInfo.environment["ROUNDEL_PNG_REPORT_DIR"] else { return }
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var forced = PNGLossyGuard.Thresholds.standard
        forced.lumaSSIM = 0; forced.channelSSIM = 0; forced.maxAlphaChange = 255; forced.maxSampledColors = Int.max; forced.bandingCollapsed = 2; forced.minShrink = -10
        for (name, png, note) in samples() {
            try png.write(to: dir.appendingPathComponent("\(name).original.png"))
            let lossless = try PNGOptimizer.optimize(png, options: .init(effort: .thorough, stripMetadata: true))
            try lossless.write(to: dir.appendingPathComponent("\(name).lossless.png"))
            let started = Date()
            let outcome = PNGColorReducer.reduce(source: png, lossless: lossless, stripMetadata: true)
            let elapsed = Date().timeIntervalSince(started)
            print("REPORT \(name) (\(note)): original \(png.count) B, lossless \(lossless.count) B")
            for a in outcome.attempts { print("REPORT   attempt \(a)") }
            if let r = outcome.result {
                try r.data.write(to: dir.appendingPathComponent("\(name).quantized.png"))
                let file = try PNGFile.parse(png), o = try XCTUnwrap(PNGPixels.rgba8(file)), q = try XCTUnwrap(PNGPixels.rgba8(try PNGFile.parse(r.data)))
                let c = PNGLossyGuard.composited(o), d = PNGLossyGuard.composited(q)
                let w = file.header.width, h = file.header.height
                let channels = (0..<3).map { String(format: "%.4f", ImageMetrics.channelSSIM(c, d, width: w, height: h, channel: $0)) }
                print("REPORT   USED: \(r.colors) colors, \(r.data.count) B (\(100 - r.data.count * 100 / lossless.count)% smaller than lossless), luma SSIM \(String(format: "%.4f", ImageMetrics.lumaSSIM(c, d, width: w, height: h))), RGB SSIM \(channels), banding share \(String(format: "%.2f", PNGLossyGuard.bandingShare(original: c, result: d, width: w, height: h))), \(String(format: "%.2f", elapsed)) s")
            } else {
                print("REPORT   REFUSED (kept lossless), \(String(format: "%.2f", elapsed)) s")
                if let f = PNGColorReducer.reduce(source: png, lossless: lossless, stripMetadata: true, thresholds: forced).result {
                    try f.data.write(to: dir.appendingPathComponent("\(name).forced.png"))
                    let file = try PNGFile.parse(png), o = try XCTUnwrap(PNGPixels.rgba8(file)), q = try XCTUnwrap(PNGPixels.rgba8(try PNGFile.parse(f.data)))
                    let c = PNGLossyGuard.composited(o), d = PNGLossyGuard.composited(q)
                    print("REPORT   (forced for the picture: \(f.colors) colors, \(f.data.count) B, luma SSIM \(String(format: "%.4f", ImageMetrics.lumaSSIM(c, d, width: file.header.width, height: file.header.height))), banding share \(String(format: "%.2f", PNGLossyGuard.bandingShare(original: c, result: d, width: file.header.width, height: file.header.height))))")
                }
            }
        }
    }
}
