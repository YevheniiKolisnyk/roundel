import XCTest
import CoreGraphics
@testable import RoundelCore

/// Strong's lossy PNG step: a median-cut palette with optional dithering, guarded so that it is used only when it is clearly
/// smaller AND looks the same (similarity, per-channel similarity, alpha, no banding, not a photograph).
final class PNGQuantizerTests: XCTestCase {
    private func rgba(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let p = f(x, y); let i = (y * w + x) * 4; out[i] = p.0; out[i + 1] = p.1; out[i + 2] = p.2; out[i + 3] = p.3 } }
        return out
    }

    /// The picture the palette stands for, as RGBA.
    private func reconstruct(_ q: QuantizedImage) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(q.indices.count * 4)
        for index in q.indices { out += q.palette[Int(index) * 4..<Int(index) * 4 + 4] }
        return out
    }

    func testAPictureWithFewColorsGetsExactlyThoseColors() {
        let colors: [(UInt8, UInt8, UInt8, UInt8)] = [(255, 255, 255, 255), (20, 20, 30, 255), (200, 40, 40, 255), (40, 120, 220, 255), (250, 200, 0, 255)]
        let a = rgba(60, 40) { x, y in colors[(x / 6 + y / 5) % colors.count] }
        for dither in [false, true] {
            let q = PNGQuantizer.quantize(rgba: a, width: 60, height: 40, maxColors: 256, dither: dither)
            XCTAssertEqual(reconstruct(q), a, "dither \(dither): nothing to approximate, nothing changes")
            XCTAssertEqual(q.count, 5)
        }
    }

    func testOpacityCountsWhenAPixelIsMatchedToAnEntry() {
        // Two entries only: a solid color A and a see-through color B. A solid pixel a little off A must go to A, not to the
        // nearer-in-color but see-through B (its alpha would be wrong by 195).
        var pixels: [UInt8] = []
        for _ in 0..<100 { pixels += [100, 150, 200, 255] }
        for _ in 0..<300 { pixels += [120, 150, 200, 60] }
        for _ in 0..<5 { pixels += [112, 150, 200, 255] }
        let q = PNGQuantizer.quantize(rgba: pixels, width: 405, height: 1, maxColors: 2, dither: false)
        let r = reconstruct(q)
        XCTAssertEqual(q.count, 2)
        for i in 400..<405 { XCTAssertEqual(r[i * 4 + 3], 255, "pixel \(i) stays solid") }
    }

    func testThePaletteNeverExceedsTheLimitAndEveryIndexIsValid() {
        var noise = TestNoise(state: 5)
        let a = rgba(80, 60) { _, _ in (UInt8(noise.next() & 255), UInt8(noise.next() & 255), UInt8(noise.next() & 255), 255) }
        for limit in [256, 64, 16, 2] {
            let q = PNGQuantizer.quantize(rgba: a, width: 80, height: 60, maxColors: limit, dither: false)
            XCTAssertLessThanOrEqual(q.count, limit)
            XCTAssertEqual(q.palette.count, q.count * 4)
            XCTAssertEqual(q.indices.count, 80 * 60)
            XCTAssertTrue(q.indices.allSatisfy { Int($0) < q.count }, "limit \(limit)")
        }
    }

    func testFullyTransparentPixelsStayFullyTransparentAndOpaqueOnesStayOpaque() {
        var noise = TestNoise(state: 8)
        let a = rgba(64, 64) { x, y in
            let inside = (x - 32) * (x - 32) + (y - 32) * (y - 32) < 600
            return inside ? (UInt8(40 + x * 3), UInt8(80 + y), UInt8(noise.next() & 255), 255) : (UInt8(noise.next() & 255), 9, 9, 0)
        }
        for dither in [false, true] {
            let r = reconstruct(PNGQuantizer.quantize(rgba: a, width: 64, height: 64, maxColors: 32, dither: dither))
            for i in 0..<(64 * 64) {
                XCTAssertEqual(r[i * 4 + 3], a[i * 4 + 3], "pixel \(i) dither \(dither): alpha is exact for 0 and 255")
            }
        }
    }

    func testTheResultIsTheSameEveryTime() {
        var noise = TestNoise(state: 2)
        let a = rgba(50, 50) { x, y in (UInt8((x * 5 + noise.next() % 9) & 255), UInt8((y * 5) & 255), 100, 255) }
        for dither in [false, true] {
            XCTAssertEqual(PNGQuantizer.quantize(rgba: a, width: 50, height: 50, maxColors: 24, dither: dither),
                           PNGQuantizer.quantize(rgba: a, width: 50, height: 50, maxColors: 24, dither: dither))
        }
    }

    func testDitheringChangesAGradientButNotAFlatPicture() {
        let ramp = rgba(256, 16) { x, _ in (UInt8(x), UInt8(x), UInt8(x), 255) }
        let plain = PNGQuantizer.quantize(rgba: ramp, width: 256, height: 16, maxColors: 8, dither: false)
        let dithered = PNGQuantizer.quantize(rgba: ramp, width: 256, height: 16, maxColors: 8, dither: true)
        XCTAssertNotEqual(plain.indices, dithered.indices)
        // Dithering keeps the local average tone: over any 8 pixels the error nearly cancels, where plain rounding is off by a whole step.
        func meanWindowError(_ q: QuantizedImage) -> Double {
            let r = reconstruct(q); var total = 0.0, windows = 0.0
            for x in stride(from: 0, to: 248, by: 4) {
                var sum = 0.0
                for k in 0..<8 { sum += Double(r[(x + k) * 4]) - Double(ramp[(x + k) * 4]) }
                total += abs(sum / 8); windows += 1
            }
            return total / windows
        }
        XCTAssertLessThan(meanWindowError(dithered), meanWindowError(plain))
        let flat = rgba(32, 32) { _, _ in (10, 200, 90, 255) }
        XCTAssertEqual(PNGQuantizer.quantize(rgba: flat, width: 32, height: 32, maxColors: 16, dither: false), PNGQuantizer.quantize(rgba: flat, width: 32, height: 32, maxColors: 16, dither: true))
    }

    func testASinglePixelOrAnEmptyPictureDoesNotBreakIt() {
        let one = PNGQuantizer.quantize(rgba: [1, 2, 3, 255], width: 1, height: 1, maxColors: 256, dither: true)
        XCTAssertEqual(reconstruct(one), [1, 2, 3, 255])
        XCTAssertEqual(PNGQuantizer.quantize(rgba: [], width: 0, height: 0, maxColors: 256, dither: false).count, 0)
        let clear = PNGQuantizer.quantize(rgba: [0, 0, 0, 0, 5, 5, 5, 0], width: 2, height: 1, maxColors: 256, dither: false)
        XCTAssertEqual(reconstruct(clear).enumerated().filter { $0.offset % 4 == 3 }.map(\.element), [0, 0])
    }
}

final class PNGLossyGuardTests: XCTestCase {
    private let t = PNGLossyGuard.Thresholds.standard
    private func rgba(_ w: Int, _ h: Int, _ f: (Int, Int) -> (Int, Int, Int, Int)) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let p = f(x, y); let i = (y * w + x) * 4
            out[i] = UInt8(max(0, min(255, p.0))); out[i + 1] = UInt8(max(0, min(255, p.1))); out[i + 2] = UInt8(max(0, min(255, p.2))); out[i + 3] = UInt8(max(0, min(255, p.3)))
        } }
        return out
    }
    private func texture(_ x: Int, _ y: Int) -> Int { 128 + Int(60 * sin(Double(x) * 0.5) * cos(Double(y) * 0.4)) + (x * 7 + y * 13) % 11 }

    func testTheAgreedThresholds() {
        XCTAssertEqual(t.minShrink, 0.30)
        XCTAssertEqual(t.lumaSSIM, 0.98)
        XCTAssertEqual(t.channelSSIM, 0.97)
        XCTAssertEqual(t.maxAlphaChange, 8)
        XCTAssertEqual(t.maxSampledColors, 8192)
        XCTAssertEqual(t.maxPixels, 24_000_000)
    }

    // MARK: Before quantizing

    func testAPictureIsTooLargeAbove24Megapixels() {
        XCTAssertNil(PNGLossyGuard.precheck(width: 6000, height: 4000, sampledColors: 10, thresholds: t))
        XCTAssertEqual(PNGLossyGuard.precheck(width: 6000, height: 4001, sampledColors: 10, thresholds: t), .tooLarge)
    }

    func testAPictureWithManyColorsIsAPhotograph() {
        XCTAssertNil(PNGLossyGuard.precheck(width: 100, height: 100, sampledColors: 8192, thresholds: t))
        XCTAssertEqual(PNGLossyGuard.precheck(width: 100, height: 100, sampledColors: 8193, thresholds: t), .photographic)
    }

    func testSampledColorsAreCountedOnASampleAndStopAtTheLimit() {
        var noise = TestNoise(state: 1)
        let photo = rgba(300, 300) { _, _ in (noise.next() & 255, noise.next() & 255, noise.next() & 255, 255) }
        XCTAssertEqual(PNGLossyGuard.sampledColors(photo, width: 300, height: 300, limit: 8192), 8193, "counting stops just past the limit")
        let flat = rgba(300, 300) { x, y in ((x / 50) * 40, (y / 50) * 40, 7, 255) }
        XCTAssertEqual(PNGLossyGuard.sampledColors(flat, width: 300, height: 300, limit: 8192), 36)
    }

    // MARK: After quantizing

    func testAnIdenticalPictureIsAccepted() {
        let a = rgba(96, 64) { x, y in let v = texture(x, y); return (v, v, v, 255) }
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: a, width: 96, height: 64, thresholds: t), .accepted)
    }

    func testAlphaMayChangeBy8ButNotBy9() {
        let a = rgba(64, 64) { x, y in (x * 3, y * 3, 100, 200) }
        func shifted(_ d: Int) -> [UInt8] { rgba(64, 64) { x, y in (x * 3, y * 3, 100, 200 + d) } }
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: shifted(8), width: 64, height: 64, thresholds: t), .accepted)
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: shifted(9), width: 64, height: 64, thresholds: t), .alphaChanged(9))
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: shifted(-9), width: 64, height: 64, thresholds: t), .alphaChanged(9))
    }

    func testAPictureWhoseStructureIsLostFailsTheLumaScore() {
        var noise = TestNoise(state: 3)
        let a = rgba(96, 64) { x, y in let v = texture(x, y); return (v, v, v, 255) }
        let b = rgba(96, 64) { x, y in let v = texture(x, y) + noise.next() % 61 - 30; return (v, v, v, 255) }
        guard case .lumaSimilarity(let score) = PNGLossyGuard.evaluate(original: a, result: b, width: 96, height: 64, thresholds: t) else { return XCTFail("luma") }
        XCTAssertLessThan(score, 0.98)
    }

    func testDamageToOneColorChannelFailsThePerChannelScoreEvenIfTheLumaHolds() {
        // Noise in blue only: blue is 11% of the luminance, so the luma score stays high, but the blue channel itself is wrecked.
        var noise = TestNoise(state: 6)
        let a = rgba(96, 64) { x, y in let v = texture(x, y); return (v, v, v, 255) }
        let b = rgba(96, 64) { x, y in let v = texture(x, y); return (v, v, v + noise.next() % 81 - 40, 255) }
        XCTAssertGreaterThanOrEqual(ImageMetrics.lumaSSIM(a, b, width: 96, height: 64), 0.98, "precondition: the luma hardly notices")
        guard case .channelSimilarity(let channel, let score) = PNGLossyGuard.evaluate(original: a, result: b, width: 96, height: 64, thresholds: t) else { return XCTFail("channel") }
        XCTAssertEqual(channel, 2); XCTAssertLessThan(score, 0.97)
    }

    func testASmoothGradientTurnedIntoBandsIsRefusedEvenThoughTheSimilarityScoreIsHigh() {
        // A ramp of one level per pixel, then posterized to steps of 4: structure scores stay high (the differences are small
        // against the metric's constants), but every 8-pixel block has collapsed to one or two colors: banding.
        let w = 256, h = 32
        let a = rgba(w, h) { x, _ in (x, x, x, 255) }
        let b = rgba(w, h) { x, _ in let v = (x / 4) * 4 + 2; return (v, v, v, 255) }
        XCTAssertGreaterThanOrEqual(ImageMetrics.similarity(a, b, width: w, height: h), 0.98, "precondition: the similarity score is fooled")
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: b, width: w, height: h, thresholds: t), .banding)
    }

    func testAVerySlowGradientTurnedIntoContoursIsRefusedToo() {
        // One level every three pixels: an 8-pixel block holds 3 or 4 colors and spans 2 or 3 levels. Posterized to steps of 4, each block
        // has one or two colors and the picture shows contour lines, which the similarity score hardly notices.
        let w = 512, h = 32
        let a = rgba(w, h) { x, _ in (40 + x / 3, 40 + x / 3, 40 + x / 3, 255) }
        let b = rgba(w, h) { x, _ in let v = ((40 + x / 3) / 4) * 4 + 2; return (v, v, v, 255) }
        XCTAssertGreaterThanOrEqual(ImageMetrics.similarity(a, b, width: w, height: h), 0.98, "precondition: the similarity score is fooled")
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: b, width: w, height: h, thresholds: t), .banding)
    }

    func testTwoFlatColorsMeetingAtALowContrastEdgeAreNotAGradient() {
        // Colors 10 levels apart look like a "smooth" block by their span, but the original has only two colors there.
        let a = rgba(64, 64) { x, _ in x < 30 ? (236, 236, 241, 255) : (246, 246, 248, 255) }
        XCTAssertEqual(PNGLossyGuard.bandingShare(original: a, result: a, width: 64, height: 64), 0)
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: a, width: 64, height: 64, thresholds: t), .accepted)
    }

    func testASmallGradientPatchInAFlatPictureIsNotWorthRefusing() {
        // One 16x16 patch of gradient (4 blocks) in a 640x360 picture (3,600 blocks): far below 3% of the picture.
        let a = rgba(640, 360) { x, y in x >= 100 && x < 116 && y >= 100 && y < 116 ? (x * 2, x * 2, x * 2, 255) : (240, 240, 245, 255) }
        let b = rgba(640, 360) { x, y in x >= 100 && x < 116 && y >= 100 && y < 116 ? (((x * 2) / 16) * 16 + 8, ((x * 2) / 16) * 16 + 8, ((x * 2) / 16) * 16 + 8, 255) : (240, 240, 245, 255) }
        XCTAssertEqual(PNGLossyGuard.bandingShare(original: a, result: b, width: 640, height: 360), 0, "too little gradient to matter")
        // The same patch, but the whole picture is gradient: refused.
        let c = rgba(640, 360) { x, _ in (x / 3, x / 3, x / 3, 255) }
        let d = rgba(640, 360) { x, _ in let v = ((x / 3) / 8) * 8 + 4; return (v, v, v, 255) }
        XCTAssertGreaterThanOrEqual(PNGLossyGuard.bandingShare(original: c, result: d, width: 640, height: 360), 0.5)
    }

    func testFlatAreasAndSharpEdgesAreNotMistakenForBanding() {
        let a = rgba(128, 64) { x, y in x < 64 ? (240, 240, 245, 255) : (30, 30, 40, 255) }
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: a, width: 128, height: 64, thresholds: t), .accepted)
        XCTAssertEqual(PNGLossyGuard.bandingShare(original: a, result: a, width: 128, height: 64), 0)
    }

    func testTransparentPixelsAreJudgedByWhatTheyLookLikeNotByTheirHiddenColor() {
        let a = rgba(64, 64) { x, y in x < 32 ? (200, 10, 10, 255) : (7, 7, 7, 0) }
        let b = rgba(64, 64) { x, y in x < 32 ? (200, 10, 10, 255) : (250, 250, 250, 0) }   // other color under alpha 0: invisible
        XCTAssertEqual(PNGLossyGuard.evaluate(original: a, result: b, width: 64, height: 64, thresholds: t), .accepted)
    }

    func testTheShrinkRuleIs30Percent() {
        XCTAssertTrue(PNGLossyGuard.isSmallEnough(lossy: 700, lossless: 1000, thresholds: t))
        XCTAssertFalse(PNGLossyGuard.isSmallEnough(lossy: 701, lossless: 1000, thresholds: t))
        XCTAssertFalse(PNGLossyGuard.isSmallEnough(lossy: 10, lossless: 0, thresholds: t))
    }

    func testBigPicturesAreScoredInBandsAndAgreeWithTheWholePictureScore() {
        var noise = TestNoise(state: 4)
        let w = 300, h = 400
        let a = rgba(w, h) { x, y in let v = texture(x, y); return (v, v, v, 255) }
        let b = rgba(w, h) { x, y in let v = texture(x, y) + noise.next() % 9 - 4; return (v, v, v, 255) }
        let whole = ImageMetrics.similarity(a, b, width: w, height: h)
        let banded = ImageMetrics.similarity(a, b, width: w, height: h, bandPixels: 30_000)
        XCTAssertEqual(banded, whole, accuracy: 0.01)
    }
}

final class PNGColorReducerTests: XCTestCase {
    private func ui(width: Int = 320, height: Int = 200, chunks: [(String, [UInt8])] = []) -> Data {
        // A screenshot-like picture: flat panels, a sidebar, rows of text whose edges are anti-aliased with colored fringes (sub-pixel
        // rendering), which gives a few thousand different colors: too many for a lossless palette, easy for a lossy one.
        var noise = TestNoise(state: 17)
        var fringe: [Int: [Int]] = [:]
        func edgeColor(_ key: Int) -> [Int] {
            if let c = fringe[key] { return c }
            let t = (0..<3).map { _ in (noise.next() % 11) * 10 }
            let c = (0..<3).map { 246 - (246 - 40) * t[$0] / 100 }
            fringe[key] = c
            return c
        }
        return TestPNG.make(.init(width: width, height: height, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            var px: [Int] = [246, 246, 248, 255]
            if y < 28 { px = [226, 226, 230, 255] }
            if x < 70 && y >= 28 { px = [236, 236, 241, 255] }
            if x >= 90 && x < 280 && (y % 12) < 8 && y > 40 {
                let glyph = ((x * 31 + (y / 12) * 17) % 7) < 4          // a pseudo-glyph pattern
                let edge = ((x * 31 + (y / 12) * 17) % 7) == 4 || ((x * 31 + (y / 12) * 17) % 7) == 3
                px = glyph ? [40, 40, 46, 255] : (edge ? edgeColor(x * 1000 + y) + [255] : [246, 246, 248, 255])
            }
            if x > 250 && y < 24 && x < 300 && y > 4 { px = [255, 95, 87, 255] }
            return px[c]
        }, chunks: chunks))
    }

    private func photo() -> Data {
        var noise = TestNoise(state: 42)
        return TestPNG.make(.init(width: 160, height: 120, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            c == 3 ? 255 : (x * 255 / 160 + y * 60 / 120 + c * 30 + noise.next() % 17) & 255 }))
    }

    private func gradient() -> Data {
        TestPNG.make(.init(width: 512, height: 64, colorType: 2, bitDepth: 8, sample: { (x: Int, _: Int, c: Int) -> Int in (x / 2 + c * 3) & 255 }))
    }

    private func lossless(_ data: Data) throws -> Data { try PNGOptimizer.optimize(data, options: .init(effort: .thorough, stripMetadata: true)) }

    func testAFlatScreenshotIsReducedToAPaletteThatIsClearlySmallerAndLooksTheSame() throws {
        let source = ui()
        let base = try lossless(source)
        let outcome = PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true)
        let result = try XCTUnwrap(outcome.result, "\(outcome.attempts)")
        XCTAssertLessThanOrEqual(Double(result.data.count), Double(base.count) * 0.70)
        let file = try PNGFile.parse(result.data)
        XCTAssertEqual(file.header.colorType, 3)
        XCTAssertEqual(file.header.width, 320); XCTAssertEqual(file.header.height, 200)
        XCTAssertLessThanOrEqual(result.colors, 256)
        let original = try XCTUnwrap(PNGPixels.rgba8(try PNGFile.parse(source))), decoded = try XCTUnwrap(PNGPixels.rgba8(file))
        XCTAssertEqual(PNGLossyGuard.evaluate(original: original, result: decoded, width: 320, height: 200, thresholds: .standard), .accepted, "what was written passes the guards")
    }

    func testAPhotographIsLeftAlone() throws {
        let source = photo()
        let outcome = PNGColorReducer.reduce(source: source, lossless: try lossless(source), stripMetadata: true)
        XCTAssertNil(outcome.result)
        XCTAssertEqual(outcome.attempts.first?.verdict, .photographic)
    }

    func testASmoothGradientIsNotQuantized() throws {
        let source = gradient()
        let outcome = PNGColorReducer.reduce(source: source, lossless: try lossless(source), stripMetadata: true)
        XCTAssertNil(outcome.result, "\(outcome.attempts)")
        XCTAssertFalse(outcome.attempts.isEmpty, "it was tried and refused, not skipped unseen")
    }

    func testTransparencyIsKeptAndTheAlphaStaysWithinTheLimit() throws {
        let source = TestPNG.make(.init(width: 128, height: 128, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            let inside = (x - 64) * (x - 64) + (y - 64) * (y - 64) < 2500
            if !inside { return c == 3 ? 0 : 0 }
            return [30, 120, 220, 255][c]
        }))
        let outcome = PNGColorReducer.reduce(source: source, lossless: try lossless(source), stripMetadata: true, thresholds: { var t = PNGLossyGuard.Thresholds.standard; t.minShrink = -10; return t }())
        let result = try XCTUnwrap(outcome.result, "\(outcome.attempts)")
        let a = try XCTUnwrap(PNGPixels.rgba8(try PNGFile.parse(source))), b = try XCTUnwrap(PNGPixels.rgba8(try PNGFile.parse(result.data)))
        for i in 0..<(128 * 128) { XCTAssertLessThanOrEqual(abs(Int(a[i * 4 + 3]) - Int(b[i * 4 + 3])), 8) }
        XCTAssertNotNil(TestPNG.chunks(of: result.data).first { $0.type == "tRNS" }, "transparency travels in tRNS")
    }

    func testChunksColorOnesStayAndTheRestIsRemovedWhenStripping() throws {
        let icc = ("iCCP", Array("p\0\0".utf8) + (Zlib.deflate([1, 2, 3, 4], level: 6) ?? []))
        let extras: [(String, [UInt8])] = [icc, ("gAMA", [0, 1, 0x86, 0xA0]), ("pHYs", [0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1]), ("tEXt", Array("A\0b".utf8)), ("tIME", [7, 233, 11, 8, 1, 2, 3])]
        let source = ui(chunks: extras)
        let stripped = try XCTUnwrap(PNGColorReducer.reduce(source: source, lossless: try lossless(source), stripMetadata: true).result)
        XCTAssertEqual(TestPNG.chunks(of: stripped.data).map(\.type).filter { !["IDAT", "IEND", "IHDR", "PLTE", "tRNS"].contains($0) }, ["iCCP", "gAMA", "pHYs"])
        let kept = try XCTUnwrap(PNGColorReducer.reduce(source: source, lossless: try lossless(source), stripMetadata: false).result)
        XCTAssertEqual(TestPNG.chunks(of: kept.data).map(\.type).filter { !["IDAT", "IEND", "IHDR", "PLTE", "tRNS"].contains($0) }, ["iCCP", "gAMA", "pHYs", "tEXt", "tIME"])
    }

    func testChunksThatNoLongerMeanAnythingAfterQuantizingAreDropped() throws {
        let extras: [(String, [UInt8])] = [("sBIT", [8, 8, 8, 8]), ("bKGD", [0, 0, 0, 0, 0, 0])]
        let source = ui(chunks: extras)
        let base = try lossless(source)
        XCTAssertTrue(TestPNG.chunks(of: base).contains { $0.type == "sBIT" }, "precondition: the lossless file keeps them")
        let result = try XCTUnwrap(PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: false).result)
        XCTAssertFalse(TestPNG.chunks(of: result.data).contains { ["sBIT", "bKGD", "hIST", "sPLT"].contains($0.type) }, "they describe the old sample format")
    }

    func testItIsUsedOnlyIfItIsAtLeast30PercentSmaller() throws {
        let source = ui()
        let base = try lossless(source)
        var strict = PNGLossyGuard.Thresholds.standard
        strict.minShrink = 0.9999
        XCTAssertNil(PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true, thresholds: strict).result)
        XCTAssertEqual(PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true, thresholds: strict).attempts.last?.verdict, .notSmallEnough)
    }

    func testItStopsTryingSmallerPalettesWhenTheTimeBudgetIsSpent() throws {
        let source = ui()
        let base = try lossless(source)
        var anything = PNGLossyGuard.Thresholds.standard
        anything.minShrink = -10   // the first palette size already counts as good enough
        let slow = PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true, thresholds: anything, timeBudget: .zero)
        XCTAssertEqual(slow.attempts.count, 1, "one palette size was tried, it passed, and the clock said stop: \(slow.attempts)")
        XCTAssertNotNil(slow.result)
        XCTAssertEqual(PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true, thresholds: anything).attempts.count, 3, "with time to spare all three palette sizes are tried")
    }

    func testAnInterlacedOrAnimatedOrHugePNGIsLeftAlone() throws {
        let interlaced = TestPNG.make(.init(width: 8, height: 8, colorType: 2, bitDepth: 8, sample: { _, _, _ in 1 }, interlace: 1))
        XCTAssertNil(PNGColorReducer.reduce(source: interlaced, lossless: interlaced, stripMetadata: true).result)
        var animated = TestPNG.Spec(width: 8, height: 8, colorType: 2, bitDepth: 8, sample: { _, _, _ in 1 })
        animated.chunks = [("acTL", [0, 0, 0, 2, 0, 0, 0, 0])]
        let apng = TestPNG.make(animated)
        XCTAssertNil(PNGColorReducer.reduce(source: apng, lossless: apng, stripMetadata: true).result)
        // A picture that would otherwise be reduced happily is left alone once it carries an animation chunk.
        let animatedUI = ui(chunks: [("acTL", [0, 0, 0, 2, 0, 0, 0, 0])])
        XCTAssertTrue(PNGColorReducer.reduce(source: animatedUI, lossless: animatedUI, stripMetadata: true).attempts.isEmpty, "not even tried")
        let plainUI = ui()
        XCTAssertFalse(PNGColorReducer.reduce(source: plainUI, lossless: try lossless(plainUI), stripMetadata: true).attempts.isEmpty, "the control: it is tried")
        XCTAssertNil(PNGColorReducer.reduce(source: Data("nope".utf8), lossless: Data(), stripMetadata: true).result)
    }

    func testSixteenBitSourcesAreHandled() throws {
        let source = TestPNG.make(.init(width: 120, height: 80, colorType: 6, bitDepth: 16, sample: { (x: Int, y: Int, c: Int) -> Int in
            let band = (x / 20 + y / 20) % 4
            return c == 3 ? 65535 : [60000, 12000, 30000, 50000][(band + c) % 4] }))
        let outcome = PNGColorReducer.reduce(source: source, lossless: try lossless(source), stripMetadata: true)
        if let r = outcome.result { XCTAssertEqual(try PNGFile.parse(r.data).header.bitDepth <= 8, true) }
        XCTAssertFalse(outcome.attempts.isEmpty)
    }

    // MARK: The guards really are what stops a bad result

    func testASabotagedQuantizerIsCaughtByTheChecksOnWhatWouldBeWritten() throws {
        let source = ui()
        let base = try lossless(source)
        func sabotaged(_ change: @escaping (inout QuantizedImage) -> Void) -> PNGColorReducer.Quantizer {
            { rgba, w, h, colors, dither in var q = PNGQuantizer.quantize(rgba: rgba, width: w, height: h, maxColors: colors, dither: dither); change(&q); return q }
        }
        // Alpha wrong everywhere.
        let alpha = PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true, quantizer: sabotaged { q in for i in 0..<q.count { q.palette[i * 4 + 3] = 200 } })
        XCTAssertNil(alpha.result); XCTAssertTrue(alpha.attempts.contains { if case .alphaChanged = $0.verdict { true } else { false } }, "\(alpha.attempts)")
        // Colors shuffled: the picture is wrong.
        let colors = PNGColorReducer.reduce(source: source, lossless: base, stripMetadata: true, quantizer: sabotaged { q in
            for i in 0..<q.count { let r = q.palette[i * 4]; q.palette[i * 4] = q.palette[i * 4 + 2]; q.palette[i * 4 + 2] = r }
        })
        XCTAssertNil(colors.result, "\(colors.attempts)")
    }
}
