import XCTest
@testable import RoundelCore

/// The safety net of the PNG optimizer: whatever it is about to write is checked against the file it was given, and a
/// result that differs in a pixel or is missing a chunk it needs is never used. These tests break the optimizer on purpose
/// (through its `Steps`) and watch the net catch it, at every level above it.
final class PNGSafetyNetTests: TempDirTestCase {
    private typealias Steps = PNGOptimizer.Steps
    private let options = PNGOptimizer.Options(effort: .light)

    // MARK: Pictures

    /// Scattered blocks of six colors, one of them transparent: the optimizer stores it as a palette with tRNS.
    private func paletteCandidate() -> Data {
        var noise = TestNoise(state: 7)
        let table: [Int] = (0..<(24 * 20)).map { _ in noise.next() % 6 }
        return TestPNG.make(.init(width: 48, height: 40, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            let k = table[(y / 2) * 24 + x / 2]
            switch c {
            case 0: return (k * 53) & 255
            case 1: return (k * 91 + 7) & 255
            case 2: return (k * 17 + 3) & 255
            default: return k == 1 ? 0 : 255
            }
        }))
    }

    /// RGB with a color profile and a resolution: recompressed only, every chunk kept.
    private func profiled() -> Data {
        let icc = ("iCCP", Array("p\0\0".utf8) + (Zlib.deflate([1, 2, 3, 4], level: 6) ?? []))
        return TestPNG.make(.init(width: 60, height: 40, colorType: 2, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in (x * 4 + y * 3 + c * 50) & 255 },
                                  chunks: [icc, ("pHYs", [0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1])]))
    }

    private func sixteenBit() -> Data {
        TestPNG.make(.init(width: 30, height: 20, colorType: 6, bitDepth: 16, sample: { (x: Int, y: Int, c: Int) -> Int in c == 3 ? 65535 : (x * 900 + y * 300 + c) & 0xFFFF }))
    }

    // MARK: Faulty steps

    /// Compresses pixels of which one byte (at `position(count)`) has been changed: a filter or deflate bug in miniature.
    private func flippingAByte(at position: @escaping (Int) -> Int) -> Steps {
        var steps = Steps.standard
        let real = steps.compress
        steps.compress = { pixels, header, plan in
            var bad = pixels
            bad[position(bad.count)] ^= 0x01
            return real(bad, header, plan)
        }
        return steps
    }

    /// Assembles the file properly, then loses (or adds, or alters) something, as a writing bug would.
    private func tamperingWithTheFile(_ change: @escaping (inout PNGFile) -> Void) -> Steps {
        var steps = Steps.standard
        let real = steps.assemble
        steps.assemble = { file, chosen, stream, options in
            guard var written = try? PNGFile.parse(real(file, chosen, stream, options)) else { return Data() }
            change(&written)
            return written.serialized()
        }
        return steps
    }

    private func assertRefused(_ source: Data, _ steps: Steps, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PNGOptimizer.optimize(source, options: options, steps: steps), message, file: file, line: line) {
            XCTAssertEqual($0 as? PNGOptimizeError, .verificationFailed, message, file: file, line: line)
        }
    }

    // MARK: The control: with nothing broken, the net lets the work through

    func testWithNothingBrokenTheNetLetsTheResultThrough() throws {
        for source in [paletteCandidate(), profiled(), sixteenBit()] {
            let result = try PNGOptimizer.optimize(source, options: options, steps: .standard)
            XCTAssertLessThan(result.count, source.count)
        }
        XCTAssertEqual(try PNGFile.parse(try PNGOptimizer.optimize(paletteCandidate(), options: options, steps: .standard)).header.colorType, 3, "precondition: this one becomes a palette")
    }

    // MARK: One wrong pixel

    func testAResultWithOneWrongPixelIsNeverReturned() {
        for (name, source) in [("palette", paletteCandidate()), ("profiled", profiled()), ("16-bit", sixteenBit())] {
            assertRefused(source, flippingAByte { _ in 0 }, "\(name): first byte")
            assertRefused(source, flippingAByte { $0 / 2 }, "\(name): middle byte")
            assertRefused(source, flippingAByte { $0 - 1 }, "\(name): last byte")
        }
    }

    // MARK: A required chunk missing

    func testAPaletteImageThatLosesItsPaletteOrItsTransparencyIsNeverReturned() {
        assertRefused(paletteCandidate(), tamperingWithTheFile { $0.chunks.removeAll { $0.type == "PLTE" } }, "no PLTE")
        assertRefused(paletteCandidate(), tamperingWithTheFile { $0.chunks.removeAll { $0.type == "tRNS" } }, "no tRNS")
    }

    func testAFileThatLosesAChunkItWasMeantToKeepIsNeverReturned() {
        assertRefused(profiled(), tamperingWithTheFile { $0.chunks.removeAll { $0.type == "iCCP" } }, "no color profile")
        assertRefused(profiled(), tamperingWithTheFile { $0.chunks.removeAll { $0.type == "pHYs" } }, "no resolution")
    }

    func testAChunkThatAppearsOutOfNowhereOrASwappedOneIsRefusedToo() {
        assertRefused(profiled(), tamperingWithTheFile { file in file.chunks.insert(PNGChunk(type: "tEXt", data: Array("a\0b".utf8)), at: 1) }, "an extra chunk")
        assertRefused(profiled(), tamperingWithTheFile { file in
            if let i = file.chunks.firstIndex(where: { $0.type == "pHYs" }) { file.chunks[i] = PNGChunk(type: "pHYs", data: [0, 0, 0, 1, 0, 0, 0, 1, 1]) }
        }, "a changed resolution")
        assertRefused(profiled(), tamperingWithTheFile { file in file.header.width += 1; file.chunks[0] = PNGChunk(type: "IHDR", data: file.header.ihdrData) }, "a changed width")
    }

    // MARK: Everything above it keeps the user's file and shows no failure

    func testConvertKeepsImageIOsFileWhenTheOptimizerIsRefused() throws {
        let source = try TestImages.write(TestImages.photo(width: 120, height: 90, grain: 0), as: "public.png", to: dir.appendingPathComponent("s.png"))
        let png = ImageFormats.format(forKey: "png")!
        let plain = dir.appendingPathComponent("plain.png")
        _ = try ImageIOEncoder(pngOptimizer: nil).encode(source: source, to: plain, format: png, options: ImageEncodingOptions())

        for (name, steps) in [("pixel", flippingAByte { $0 / 2 }), ("chunk", tamperingWithTheFile { $0.chunks.removeAll { $0.type == "pHYs" || $0.type == "iCCP" || $0.type == "sRGB" } })] {
            let broken = ImageIOEncoder(pngOptimizer: { try PNGOptimizer.optimize($0, options: PNGOptimizer.Options(effort: .light), steps: steps) })
            let out = dir.appendingPathComponent("out-\(name).png")
            XCTAssertNoThrow(try broken.encode(source: source, to: out, format: png, options: ImageEncodingOptions()), "the conversion does not fail")
            XCTAssertEqual(try Data(contentsOf: out), try Data(contentsOf: plain), "\(name): ImageIO's own file is what is kept")
        }
        XCTAssertFalse(listing().contains { $0.hasSuffix(".tmp") })
    }

    func testCompressTreatsARefusedResultAsAlreadyOptimalWritingNothing() async throws {
        let source = dir.appendingPathComponent("big.png")
        try paletteCandidate().write(to: source)   // an unoptimized file that would normally shrink
        for (name, steps) in [("pixel", flippingAByte { $0 / 2 }), ("palette", tamperingWithTheFile { $0.chunks.removeAll { $0.type == "PLTE" } })] {
            let compressor = ImageCompressor(encoder: ImageIOEncoder(), pngOptimizer: { try PNGOptimizer.optimize($0, options: $1, steps: steps) })
            let results = await compressor.compress(files: [source], options: CompressionOptions(), progress: { _, _ in })
            XCTAssertEqual(results, [.alreadyOptimal(source: source)], name)
            XCTAssertEqual(listing(), ["big.png"], "\(name): nothing written, nothing left over")
        }
        // And without the fault the same file is compressed.
        let fine = await ImageCompressor(encoder: ImageIOEncoder()).compress(files: [source], options: CompressionOptions(), progress: { _, _ in })
        guard case .compressed? = fine.first else { return XCTFail("\(fine)") }
    }

    // MARK: The checker itself

    func testTheCheckerTellsTheSamePictureInDifferentClothesFromADifferentOne() throws {
        let rgba = paletteCandidate()
        let palette = try PNGOptimizer.optimize(rgba, options: options)
        XCTAssertEqual(try PNGFile.parse(palette).header.colorType, 3)
        let source = try PNGFile.parse(rgba)
        let raw = try XCTUnwrap(Zlib.inflate(source.imageData, limit: 1 << 20))
        XCTAssertTrue(PNGVerifier.verify(source: source, sourceRaw: raw, result: palette, stripMetadata: false, addedChunkTypes: ["PLTE", "tRNS"]), "RGBA and its palette form are the same picture")

        // One pixel's alpha changed in the palette form's source picture: not the same picture.
        var other = TestPNG.Spec(width: 48, height: 40, colorType: 6, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in
            c == 3 ? (x == 5 && y == 5 ? 17 : 255) : (x + y) & 255 })
        other.level = 1
        let different = TestPNG.make(other)
        XCTAssertFalse(PNGVerifier.verify(source: source, sourceRaw: raw, result: different, stripMetadata: false, addedChunkTypes: []))
    }

    func testTheReferenceUnfilteringAgreesWithTheOptimizersOwn() {
        var noise = TestNoise(state: 3)
        for (rowBytes, step) in [(30, 3), (32, 4), (17, 1), (64, 8)] {
            let height = 7
            let pixels = (0..<(rowBytes * height)).map { _ in UInt8(noise.next() & 255) }
            for strategy in PNGFilter.Strategy.allCases {
                let filtered = PNGFilter.filter(pixels, rowBytes: rowBytes, height: height, step: step, strategy: strategy)
                XCTAssertEqual(PNGVerifier.unfilterAll(filtered, rowBytes: rowBytes, height: height, step: step), pixels, "\(strategy) rowBytes \(rowBytes)")
            }
        }
    }
}
