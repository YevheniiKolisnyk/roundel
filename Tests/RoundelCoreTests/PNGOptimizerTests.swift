import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

/// The lossless PNG optimizer. Every test compares pixels with an independent reader (`TestPNG.decode`).
final class PNGOptimizerTests: XCTestCase {
    private let thorough = PNGOptimizer.Options(effort: .thorough, stripMetadata: false)
    private let light = PNGOptimizer.Options(effort: .light, stripMetadata: false)

    private func optimize(_ data: Data, _ options: PNGOptimizer.Options? = nil) throws -> Data { try PNGOptimizer.optimize(data, options: options ?? thorough) }

    private func header(_ data: Data) throws -> PNGHeader { try PNGFile.parse(data).header }

    /// The pictures: smooth gradients with a little structure, the way a screenshot or a render looks.
    private func gradient(_ w: Int, _ h: Int, colorType: Int, depth: Int = 8, seed: UInt32 = 1, extra: [(String, [UInt8])] = [], palette: [UInt8]? = nil) -> TestPNG.Spec {
        let maxValue = (1 << depth) - 1
        let span = w * 3 + h * 2 + 160
        return TestPNG.Spec(width: w, height: h, colorType: colorType, bitDepth: depth, sample: { (x: Int, y: Int, c: Int) -> Int in
            let ramp: Int = (x * 3 + y * 2 + c * 40) * maxValue / span
            let bump: Int = (x / 7 + y / 5) % 3 == 0 ? maxValue / 16 : 0
            return min(maxValue, max(0, ramp + bump))
        }, palette: palette, chunks: extra)
    }

    private func assertSamePixels(_ a: Data, _ b: Data, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let x = try XCTUnwrap(TestPNG.decode(a), "source decodes", file: file, line: line)
        let y = try XCTUnwrap(TestPNG.decode(b), "result decodes", file: file, line: line)
        XCTAssertEqual(x.width, y.width, message, file: file, line: line)
        XCTAssertEqual(x.height, y.height, message, file: file, line: line)
        XCTAssertTrue(x.rgba16 == y.rgba16, "pixels differ \(message)", file: file, line: line)
    }

    // MARK: Recompression keeps the pixels and shrinks an unoptimized file

    func testEveryColorTypeAndBitDepthKeepsItsPixelsAndTheFileGetsSmaller() throws {
        let combos: [(Int, Int)] = [(0, 1), (0, 2), (0, 4), (0, 8), (0, 16), (2, 8), (2, 16), (3, 1), (3, 2), (3, 4), (3, 8), (4, 8), (4, 16), (6, 8), (6, 16)]
        for (type, depth) in combos {
            var spec = gradient(61, 37, colorType: type, depth: depth)
            if type == 3 { spec.palette = Self.ramp(entries: 1 << depth) }
            let source = TestPNG.make(spec)
            let result = try optimize(source)
            try assertSamePixels(source, result, "type \(type) depth \(depth)")
            XCTAssertLessThanOrEqual(result.count, source.count, "type \(type) depth \(depth)")
            XCTAssertNotNil(CGImageSourceCreateWithData(result as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }, "ImageIO opens type \(type) depth \(depth)")
        }
    }

    func testAnUnoptimizedGradientShrinksALot() throws {
        let source = TestPNG.make(gradient(240, 160, colorType: 2))
        let result = try optimize(source)
        XCTAssertLessThan(Double(result.count), Double(source.count) * 0.6, "\(source.count) -> \(result.count)")
    }

    func testAFileWithColorChunksIsRecompressedButKeepsItsColorTypeAndEveryChunk() throws {
        // Chunks whose meaning depends on the sample format: no reductions, whatever the pixels allow.
        let colorChunks: [(String, [UInt8])] = [("gAMA", [0, 1, 0x86, 0xA0]), ("cHRM", [UInt8](repeating: 1, count: 32)), ("sRGB", [0]), ("sBIT", [8, 8, 8, 8]),
                                                ("iCCP", Array("p\0\0".utf8) + (Zlib.deflate([1, 2, 3, 4], level: 6) ?? [])), ("bKGD", [0, 0, 0, 0, 0, 0]), ("tRNS", [0, 0, 0, 0, 0, 0])]
        for (name, bytes) in colorChunks {
            // An opaque, gray RGBA picture: reducible in principle.
            var spec = TestPNG.Spec(width: 40, height: 30, colorType: name == "tRNS" || name == "bKGD" ? 2 : 6, bitDepth: 8, sample: { x, y, c in c == 3 ? 255 : (x * 5 + y * 3) & 255 })
            spec.chunks = [(name, bytes)]
            let source = TestPNG.make(spec)
            let result = try optimize(source)
            XCTAssertEqual(try header(result), try header(source), "\(name) present: color type and depth stay")
            let before = TestPNG.chunks(of: source).filter { $0.type != "IDAT" }
            let after = TestPNG.chunks(of: result).filter { $0.type != "IDAT" }
            XCTAssertEqual(after, before, "\(name): every other chunk kept, in order")
            try assertSamePixels(source, result, name)
        }
    }

    func testUnknownAncillaryChunksAlsoForbidReductionsAndAreKept() throws {
        var spec = gradient(30, 20, colorType: 6)
        spec.sample = { x, y, c in c == 3 ? 255 : (x + y) & 255 }
        spec.chunks = [("prVW", [1, 2, 3]), ("pHYs", [0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1])]
        let source = TestPNG.make(spec)
        let result = try optimize(source)
        XCTAssertEqual(try header(result).colorType, 6)
        XCTAssertEqual(TestPNG.chunks(of: result).map(\.type), ["IHDR", "prVW", "pHYs", "IDAT", "IEND"])
    }

    func testTextAndResolutionChunksDoNotStopReductionsAndSurviveThem() throws {
        var spec = TestPNG.Spec(width: 40, height: 30, colorType: 6, bitDepth: 8, sample: { x, y, c in c == 3 ? 255 : (x * 5 + y * 3 + c) & 255 })
        let text = ("tEXt", Array("Comment\0hello".utf8)), phys = ("pHYs", [UInt8]([0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1])), time = ("tIME", [UInt8]([7, 233, 11, 8, 1, 2, 3]))
        spec.chunks = [phys, text, time]
        let source = TestPNG.make(spec)
        let result = try optimize(source)
        XCTAssertEqual(try header(result).colorType, 2, "opaque RGBA becomes RGB")
        XCTAssertEqual(TestPNG.chunks(of: result).filter { $0.type != "IDAT" }.map(\.type), ["IHDR", "pHYs", "tEXt", "tIME", "IEND"])
        XCTAssertEqual(TestPNG.chunks(of: result).first { $0.type == "tEXt" }?.data, text.1)
        try assertSamePixels(source, result)
    }

    // MARK: Lossless reductions

    func testReductionsOfColorTypeWhenTheyLoseNothing() throws {
        // (source type, picture, expected type)
        let cases: [(String, TestPNG.Spec, Int)] = [
            ("opaque RGBA -> RGB", .init(width: 50, height: 40, colorType: 6, bitDepth: 8, sample: { x, y, c in c == 3 ? 255 : (x * 5 + y * 7 + c * 31) & 255 }), 2),
            ("gray RGB -> gray", .init(width: 50, height: 40, colorType: 2, bitDepth: 8, sample: { x, y, _ in (x * 5 + y * 7) & 255 }), 0),
            ("opaque gray+alpha -> gray", .init(width: 50, height: 40, colorType: 4, bitDepth: 8, sample: { x, y, c in c == 1 ? 255 : (x * 5 + y * 7) & 255 }), 0),
            ("gray RGBA with alpha -> gray+alpha", .init(width: 50, height: 40, colorType: 6, bitDepth: 8, sample: { x, y, c in c == 3 ? (x * 6) & 255 : (x * 5 + y * 7) & 255 }), 4),
            ("opaque gray RGBA -> gray", .init(width: 50, height: 40, colorType: 6, bitDepth: 8, sample: { x, y, c in c == 3 ? 255 : (x * 5 + y * 7) & 255 }), 0),
        ]
        for (name, spec, expected) in cases {
            let source = TestPNG.make(spec)
            let result = try optimize(source)
            XCTAssertEqual(try header(result).colorType, expected, name)
            XCTAssertEqual(try header(result).bitDepth, 8, name)
            try assertSamePixels(source, result, name)
        }
    }

    func testAPictureWithRealColorAndTransparencyIsNotReduced() throws {
        // One non-opaque pixel and many different colors: nothing may be dropped.
        let spec = TestPNG.Spec(width: 64, height: 64, colorType: 6, bitDepth: 8, sample: { x, y, c in
            if c == 3 { return x == 3 && y == 4 ? 200 : 255 }
            return (x * 4 + y * 3 + c * 70) & 255
        })
        let source = TestPNG.make(spec)
        let result = try optimize(source)
        XCTAssertEqual(try header(result).colorType, 6)
        try assertSamePixels(source, result)
    }

    func testFewColorsBecomeAPaletteWithTheRightBitDepthAndTransparency() throws {
        // Scattered blocks of `colors` different colors: as RGB it is hard to compress, as indices it is small. (A tidy
        // diagonal pattern would compress to almost nothing as RGB and a palette would rightly lose.)
        func make(colors: Int, alpha: Bool) -> TestPNG.Spec {
            var noise = TestNoise(state: UInt32(colors))
            let table: [Int] = (0..<(24 * 20)).map { _ in noise.next() % colors }
            return TestPNG.Spec(width: 48, height: 40, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
                let k = table[(y / 2) * 24 + x / 2]
                switch c {
                case 0: return (k * 53) & 255
                case 1: return (k * 91 + 7) & 255
                case 2: return (k * 17 + 3) & 255
                default: return alpha && k == 1 ? 0 : 255
                }
            })
        }
        for (colors, depth) in [(2, 1), (3, 2), (4, 2), (5, 4), (16, 4), (17, 8), (200, 8)] {
            let source = TestPNG.make(make(colors: colors, alpha: false))
            let result = try optimize(source)
            let h = try header(result)
            XCTAssertEqual(h.colorType, 3, "\(colors) colors")
            XCTAssertEqual(h.bitDepth, depth, "\(colors) colors")
            try assertSamePixels(source, result, "\(colors) colors")
            XCTAssertLessThan(result.count, source.count)
        }
        let withAlpha = TestPNG.make(make(colors: 6, alpha: true))
        let result = try optimize(withAlpha)
        XCTAssertEqual(try header(result).colorType, 3)
        XCTAssertNotNil(TestPNG.chunks(of: result).first { $0.type == "tRNS" }, "transparency travels in tRNS")
        try assertSamePixels(withAlpha, result, "palette with alpha")
    }

    func testMoreThan256ColorsNeverBecomeAPalette() throws {
        let spec = TestPNG.Spec(width: 40, height: 40, colorType: 2, bitDepth: 8, sample: { x, y, c in (x * 6 + y * 11 + c * 37) & 255 })
        let result = try optimize(TestPNG.make(spec))
        XCTAssertEqual(try header(result).colorType, 2)
    }

    func testSixteenBitAndPaletteFilesAreOnlyRecompressed() throws {
        let sixteen = TestPNG.make(.init(width: 30, height: 20, colorType: 6, bitDepth: 16, sample: { x, y, c in c == 3 ? 65535 : (x * 900 + y * 300 + c) & 0xFFFF }))
        XCTAssertEqual(try header(try optimize(sixteen)), PNGHeader(width: 30, height: 20, bitDepth: 16, colorType: 6))
        var spec = gradient(30, 20, colorType: 3, depth: 8)
        spec.palette = Self.ramp(entries: 256)
        let paletted = TestPNG.make(spec)
        XCTAssertEqual(try header(try optimize(paletted)).colorType, 3)
    }

    func testTheSmallestOfTheCandidatesWins() throws {
        // Opaque gray stored as RGBA: the gray candidate must beat both the RGBA recompression and a 256-entry palette.
        let spec = TestPNG.Spec(width: 120, height: 80, colorType: 6, bitDepth: 8, sample: { x, y, c in c == 3 ? 255 : (x + y * 2) & 255 })
        let source = TestPNG.make(spec)
        let result = try optimize(source)
        XCTAssertEqual(try header(result).colorType, 0)
    }

    // MARK: Metadata

    func testStrippingRemovesTextTimeAndPlainExifButKeepsColorAndResolution() throws {
        var spec = gradient(30, 20, colorType: 2)
        let icc = ("iCCP", Array("p\0\0".utf8) + (Zlib.deflate([1, 2, 3, 4], level: 6) ?? []))
        let phys = ("pHYs", [UInt8]([0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1]))
        spec.chunks = [icc, phys, ("tEXt", Array("A\0b".utf8)), ("zTXt", Array("A\0\0".utf8) + (Zlib.deflate([1], level: 6) ?? [])), ("iTXt", Array("XML:com.adobe.xmp\0\0\0\0\0<x/>".utf8)), ("tIME", [7, 233, 11, 8, 1, 2, 3]), ("eXIf", Self.exif(orientation: nil))]
        let result = try optimize(TestPNG.make(spec), .init(effort: .light, stripMetadata: true))
        XCTAssertEqual(TestPNG.chunks(of: result).map(\.type), ["IHDR", "iCCP", "pHYs", "IDAT", "IEND"])
    }

    func testStrippingKeepsAnExifBlockThatCarriesARotationSoTheImageStaysUpright() throws {
        var spec = gradient(30, 20, colorType: 2)
        spec.chunks = [("eXIf", Self.exif(orientation: 6)), ("tEXt", Array("A\0b".utf8))]
        let result = try optimize(TestPNG.make(spec), .init(effort: .light, stripMetadata: true))
        XCTAssertEqual(TestPNG.chunks(of: result).map(\.type), ["IHDR", "eXIf", "IDAT", "IEND"])
        var upright = gradient(30, 20, colorType: 2)
        upright.chunks = [("eXIf", Self.exif(orientation: 1))]
        XCTAssertFalse(TestPNG.chunks(of: try optimize(TestPNG.make(upright), .init(effort: .light, stripMetadata: true))).contains { $0.type == "eXIf" })
    }

    func testWithoutStrippingEveryChunkIsKept() throws {
        var spec = gradient(30, 20, colorType: 2)
        spec.chunks = [("tEXt", Array("A\0b".utf8)), ("eXIf", Self.exif(orientation: 6)), ("tIME", [7, 233, 11, 8, 1, 2, 3])]
        let result = try optimize(TestPNG.make(spec))
        XCTAssertEqual(TestPNG.chunks(of: result).map(\.type), ["IHDR", "tEXt", "eXIf", "tIME", "IDAT", "IEND"])
    }

    /// `entries` palette colors (r, g, b each), all different enough.
    static func ramp(entries: Int) -> [UInt8] {
        var out: [UInt8] = []
        for i in 0..<entries {
            out.append(UInt8((i * 5) & 255))
            out.append(UInt8((i * 9) & 255))
            out.append(UInt8((i * 3) & 255))
        }
        return out
    }

    /// A little-endian EXIF block with an IFD0 of one entry (Orientation) or none.
    static func exif(orientation: Int?) -> [UInt8] {
        guard let orientation else { return [0x49, 0x49, 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0] }
        return [0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, UInt8(orientation), 0, 0, 0, 0, 0, 0, 0]
    }

    // MARK: Properties

    func testOptimizingTwiceChangesNothingMore() throws {
        var pictures: [Data] = []
        pictures.append(TestPNG.make(gradient(90, 60, colorType: 2)))
        pictures.append(TestPNG.make(.init(width: 50, height: 40, colorType: 6, bitDepth: 8, sample: { x, y, c in c == 3 ? 255 : (x * 5 + y * 7 + c * 31) & 255 })))
        pictures.append(TestPNG.make(.init(width: 48, height: 40, colorType: 6, bitDepth: 8, sample: { x, y, c in let k = (x / 4 + y / 4) % 5; return c == 3 ? (k == 1 ? 0 : 255) : (k * 50 + c * 9) & 255 })))
        pictures.append(TestPNG.make(gradient(33, 21, colorType: 0, depth: 4)))
        pictures.append(TestPNG.make(gradient(33, 21, colorType: 6, depth: 16)))
        for options in [thorough, light] {
            for source in pictures {
                let once = try optimize(source, options)
                let twice = try optimize(once, options)
                XCTAssertEqual(twice, once, "\(options.effort)")
            }
        }
    }

    func testThoroughIsNeverBiggerThanLight() throws {
        for spec in [gradient(200, 120, colorType: 2), gradient(120, 90, colorType: 6), gradient(80, 80, colorType: 0, depth: 16)] {
            let source = TestPNG.make(spec)
            XCTAssertLessThanOrEqual(try optimize(source, thorough).count, try optimize(source, light).count)
        }
    }

    func testRandomNoiseSurvivesEvenThoughItCannotShrink() throws {
        var n = TestNoise(state: 99)
        let spec = TestPNG.Spec(width: 64, height: 64, colorType: 6, bitDepth: 8, sample: { _, _, _ in n.next() & 255 })
        let source = TestPNG.make(spec)
        let result = try optimize(source)
        try assertSamePixels(source, result)
    }

    func testAFileWithAnEnormousDimensionPromiseDoesNotBalloon() {
        // 100000 x 100000 pixels promised by the header, but only a few bytes of image data: refused, not allocated.
        var header = PNGHeader(width: 100_000, height: 100_000, bitDepth: 8, colorType: 6)
        header.interlace = 0
        let file = PNGFile(header: header, chunks: [PNGChunk(type: "IHDR", data: header.ihdrData), PNGChunk(type: "IDAT", data: Zlib.deflate([0, 0, 0], level: 6)!), PNGChunk(type: "IEND", data: [])])
        XCTAssertThrowsError(try optimize(file.serialized())) { XCTAssertEqual($0 as? PNGOptimizeError, .damaged) }
    }

    // MARK: What is refused

    func testInterlacedApngDamagedAndNonPngFilesAreRefusedWithTheRightReason() throws {
        let interlaced = TestPNG.make(.init(width: 8, height: 8, colorType: 2, bitDepth: 8, sample: { x, _, _ in x }, interlace: 1))
        XCTAssertThrowsError(try optimize(interlaced)) { XCTAssertEqual($0 as? PNGOptimizeError, .interlaced) }

        var apng = gradient(8, 8, colorType: 2)
        apng.chunks = [("acTL", [0, 0, 0, 2, 0, 0, 0, 0])]
        XCTAssertThrowsError(try optimize(TestPNG.make(apng))) { XCTAssertEqual($0 as? PNGOptimizeError, .animated) }

        let good = TestPNG.make(gradient(8, 8, colorType: 2))
        XCTAssertThrowsError(try optimize(good.prefix(good.count - 9))) { XCTAssertEqual($0 as? PNGOptimizeError, .damaged) }
        XCTAssertThrowsError(try optimize(Data("hello".utf8))) { XCTAssertEqual($0 as? PNGOptimizeError, .notPNG) }

        // Image data that inflates to the wrong amount.
        let header = PNGHeader(width: 8, height: 8, bitDepth: 8, colorType: 2)
        let short = PNGFile(header: header, chunks: [PNGChunk(type: "IHDR", data: header.ihdrData), PNGChunk(type: "IDAT", data: Zlib.deflate([UInt8](repeating: 0, count: 100), level: 6)!), PNGChunk(type: "IEND", data: [])])
        XCTAssertThrowsError(try optimize(short.serialized())) { XCTAssertEqual($0 as? PNGOptimizeError, .damaged) }
    }

    func testAFileWithAnUnknownCriticalChunkIsUnsupported() {
        var spec = gradient(8, 8, colorType: 2)
        spec.chunks = [("XXXX", [1])]
        XCTAssertThrowsError(try optimize(TestPNG.make(spec))) { XCTAssertEqual($0 as? PNGOptimizeError, .unsupported) }
    }

    // MARK: How hard it tries depends on how big the picture is

    func testTheSearchEffortDependsOnTheSizeAndOnHowFlatThePictureIs() {
        let mib = 1 << 20
        // Light is always quick.
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .light, rawBytes: 10, sampleRatio: 0.01), .quick)
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .light, rawBytes: 500 * mib, sampleRatio: 0.01), .quick)
        // Small pictures get the full search however noisy they are.
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .thorough, rawBytes: 1 * mib, sampleRatio: 0.9), .full)
        // Bigger: only flat ones get it, noisy ones a medium search.
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .thorough, rawBytes: 20 * mib, sampleRatio: 0.25), .full, "a screenshot")
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .thorough, rawBytes: 20 * mib, sampleRatio: 0.26), .ranked, "a photograph")
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .thorough, rawBytes: 1 * mib + 1, sampleRatio: 0.9), .ranked)
        // Beyond 32 MiB of pixel data thorough would take minutes.
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .thorough, rawBytes: 32 * mib, sampleRatio: 0.9), .ranked)
        XCTAssertEqual(PNGOptimizer.searchPlan(effort: .thorough, rawBytes: 32 * mib + 1, sampleRatio: 0.01), .quick)
    }

    func testTheSampleRatioTellsFlatFromNoisy() throws {
        let flat = try PNGFile.parse(TestPNG.make(.init(width: 300, height: 300, colorType: 2, bitDepth: 8, sample: { x, y, _ in (x / 50 + y / 50) * 20 })))
        var noise = TestNoise(state: 5)
        let noisy = try PNGFile.parse(TestPNG.make(.init(width: 300, height: 300, colorType: 2, bitDepth: 8, sample: { _, _, _ in noise.next() & 255 })))
        func ratio(_ file: PNGFile) throws -> Double {
            let h = file.header
            let raw = try XCTUnwrap(Zlib.inflate(file.imageData, limit: h.height * (h.rowBytes + 1)))
            let pixels = try XCTUnwrap(PNGFilter.unfilter(raw, rowBytes: h.rowBytes, height: h.height, step: h.filterStep))
            return PNGOptimizer.sampleRatio(of: PNGCandidate(header: h, pixels: pixels))
        }
        XCTAssertLessThan(try ratio(flat), PNGOptimizer.flatSampleRatio)
        XCTAssertGreaterThan(try ratio(noisy), PNGOptimizer.flatSampleRatio)
    }

    func testARankedSearchStillBeatsTheQuickOne() throws {
        // Force the ranked plan on a small picture through the same code path and compare with the quick one.
        let source = TestPNG.make(gradient(240, 160, colorType: 2))
        let file = try PNGFile.parse(source)
        let h = file.header
        let raw = try XCTUnwrap(Zlib.inflate(file.imageData, limit: h.height * (h.rowBytes + 1)))
        let pixels = try XCTUnwrap(PNGFilter.unfilter(raw, rowBytes: h.rowBytes, height: h.height, step: h.filterStep))
        let quick = try XCTUnwrap(PNGOptimizer.compress(pixels, header: h, plan: .quick))
        let ranked = try XCTUnwrap(PNGOptimizer.compress(pixels, header: h, plan: .ranked))
        let full = try XCTUnwrap(PNGOptimizer.compress(pixels, header: h, plan: .full))
        XCTAssertLessThanOrEqual(ranked.count, quick.count, "it tries the quick one's way too")
        XCTAssertLessThanOrEqual(full.count, ranked.count)
        for packed in [quick, ranked, full] {
            let again = try XCTUnwrap(Zlib.inflate(packed, limit: h.height * (h.rowBytes + 1)))
            XCTAssertEqual(PNGFilter.unfilter(again, rowBytes: h.rowBytes, height: h.height, step: h.filterStep), pixels, "every plan is lossless")
        }
    }

    // MARK: Real files from the system's own encoder

    func testAnImageIOWrittenPNGKeepsItsPixelsUnderImageIOToo() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for i in 0..<12 {
            context.setFillColor(red: CGFloat(i) / 12, green: 0.5, blue: 1 - CGFloat(i) / 12, alpha: i == 5 ? 0.5 : 1)
            context.fill(CGRect(x: i * 10, y: 0, width: 10, height: 80))
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))

        let result = try optimize(data as Data)
        func rgba(_ d: Data) throws -> [UInt8] {
            let img = try XCTUnwrap(CGImageSourceCreateWithData(d as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            var out = [UInt8](repeating: 0, count: 120 * 80 * 4)
            let ctx = try XCTUnwrap(CGContext(data: &out, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 480, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 120, height: 80))
            return out
        }
        XCTAssertEqual(try rgba(result), try rgba(data as Data), "ImageIO sees the same picture")
        XCTAssertLessThan(result.count, data.length)
    }
}
