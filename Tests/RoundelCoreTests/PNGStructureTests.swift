import XCTest
@testable import RoundelCore

final class PNGStructureTests: XCTestCase {
    private func sampleFile() -> Data {
        TestPNG.make(.init(width: 5, height: 4, colorType: 2, bitDepth: 8, sample: { x, y, c in (x * 40 + y * 10 + c * 3) & 255 }, chunks: [("pHYs", [0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1])]))
    }

    func testAFileParsesAndWritesBackByteForByte() throws {
        let data = sampleFile()
        let file = try PNGFile.parse(data)
        XCTAssertEqual(file.header, PNGHeader(width: 5, height: 4, bitDepth: 8, colorType: 2))
        XCTAssertEqual(file.chunks.map(\.type), ["IHDR", "pHYs", "IDAT", "IEND"])
        XCTAssertEqual(file.serialized(), data)
    }

    func testAWrongChecksumMeansDamaged() {
        var bytes = [UInt8](sampleFile())
        bytes[bytes.count - 20] ^= 0x55   // inside the image data
        XCTAssertThrowsError(try PNGFile.parse(Data(bytes))) { XCTAssertEqual($0 as? PNGOptimizeError, .damaged) }
    }

    func testATruncatedFileIsDamagedAndNonPNGIsRefused() {
        let data = sampleFile()
        XCTAssertThrowsError(try PNGFile.parse(data.prefix(data.count - 14))) { XCTAssertEqual($0 as? PNGOptimizeError, .damaged) }
        XCTAssertThrowsError(try PNGFile.parse(Data("not a png at all".utf8))) { XCTAssertEqual($0 as? PNGOptimizeError, .notPNG) }
        XCTAssertThrowsError(try PNGFile.parse(Data())) { XCTAssertEqual($0 as? PNGOptimizeError, .notPNG) }
    }

    func testImpossibleHeadersAreUnsupported() {
        for (type, depth) in [(2, 4), (3, 16), (4, 1), (6, 2), (5, 8)] {
            var chunks = [PNGChunk(type: "IHDR", data: [0, 0, 0, 1, 0, 0, 0, 1, UInt8(depth), UInt8(type), 0, 0, 0]), PNGChunk(type: "IDAT", data: [1]), PNGChunk(type: "IEND", data: [])]
            _ = chunks.removeFirst().type
            let bad = PNGFile.signature + PNGChunk(type: "IHDR", data: [0, 0, 0, 1, 0, 0, 0, 1, UInt8(depth), UInt8(type), 0, 0, 0]).serialized() + chunks.flatMap { $0.serialized() }
            XCTAssertThrowsError(try PNGFile.parse(Data(bad)), "type \(type) depth \(depth)") { XCTAssertEqual($0 as? PNGOptimizeError, .unsupported) }
        }
    }

    func testHeaderArithmetic() {
        let rgba16 = PNGHeader(width: 10, height: 2, bitDepth: 16, colorType: 6)
        XCTAssertEqual(rgba16.rowBytes, 80); XCTAssertEqual(rgba16.filterStep, 8)
        let gray1 = PNGHeader(width: 10, height: 2, bitDepth: 1, colorType: 0)
        XCTAssertEqual(gray1.rowBytes, 2); XCTAssertEqual(gray1.filterStep, 1)
        let palette4 = PNGHeader(width: 3, height: 1, bitDepth: 4, colorType: 3)
        XCTAssertEqual(palette4.rowBytes, 2)
    }

    func testChunkClassesAndRoundTrip() {
        XCTAssertTrue(PNGChunk(type: "tEXt", data: []).isAncillary)
        XCTAssertFalse(PNGChunk(type: "PLTE", data: []).isAncillary)
        let chunk = PNGChunk(type: "tEXt", data: Array("k\0v".utf8))
        XCTAssertEqual(chunk.serialized().count, 12 + 3)
    }
}

final class PNGFilterTests: XCTestCase {
    private func noise(_ count: Int, seed: UInt32 = 5) -> [UInt8] {
        var n = TestNoise(state: seed)
        return (0..<count).map { i in i % 5 == 0 ? UInt8(n.next() & 255) : UInt8((i / 3) & 255) }
    }

    func testEveryStrategyUndoesExactlyForEveryPixelSizeAndRowWidth() {
        for step in [1, 2, 3, 4, 6, 8] {
            for rowBytes in [step, step * 3 + (step > 1 ? 0 : 1), 37 * step] {
                let height = 9
                let pixels = noise(rowBytes * height, seed: UInt32(rowBytes))
                for strategy in PNGFilter.Strategy.allCases {
                    let filtered = PNGFilter.filter(pixels, rowBytes: rowBytes, height: height, step: step, strategy: strategy)
                    XCTAssertEqual(filtered.count, height * (rowBytes + 1))
                    XCTAssertEqual(PNGFilter.unfilter(filtered, rowBytes: rowBytes, height: height, step: step), pixels, "step \(step) row \(rowBytes) \(strategy)")
                }
            }
        }
    }

    func testFixedStrategiesWriteTheirTypeByteOnEveryRow() {
        let pixels = noise(10 * 6)
        for strategy in PNGFilter.Strategy.allCases {
            guard let type = strategy.fixedType else { continue }
            let filtered = PNGFilter.filter(pixels, rowBytes: 10, height: 6, step: 1, strategy: strategy)
            XCTAssertEqual((0..<6).map { filtered[$0 * 11] }, [UInt8](repeating: type, count: 6), "\(strategy)")
        }
    }

    func testTheAdaptiveHeuristicPicksTheRowFilterWithTheSmallestSum() {
        // A smooth horizontal ramp: Sub makes every byte after the first a constant 1; "None" leaves large numbers.
        let rowBytes = 64
        let pixels = (0..<8).flatMap { _ in (0..<rowBytes).map { UInt8($0) } }
        let filtered = PNGFilter.filter(pixels, rowBytes: rowBytes, height: 8, step: 1, strategy: .adaptive)
        let types = (0..<8).map { filtered[$0 * (rowBytes + 1)] }
        XCTAssertTrue(types.allSatisfy { $0 != 0 }, "none is the worst here: \(types)")
        // Rows after the first repeat the row above exactly: Up gives all zeros, the best possible.
        XCTAssertEqual(types.dropFirst().map { $0 }, [UInt8](repeating: 2, count: 7))
    }

    func testBadFilterBytesAndWrongSizesAreRefused() {
        var filtered = PNGFilter.filter(noise(20), rowBytes: 10, height: 2, step: 1, strategy: .sub)
        XCTAssertNotNil(PNGFilter.unfilter(filtered, rowBytes: 10, height: 2, step: 1))
        filtered[0] = 5
        XCTAssertNil(PNGFilter.unfilter(filtered, rowBytes: 10, height: 2, step: 1))
        XCTAssertNil(PNGFilter.unfilter(Array(filtered.dropLast()), rowBytes: 10, height: 2, step: 1))
    }

    func testPaethPredictor() {
        XCTAssertEqual(PNGFilter.paeth(10, 10, 10), 10)
        XCTAssertEqual(PNGFilter.paeth(0, 20, 0), 20)
        XCTAssertEqual(PNGFilter.paeth(20, 0, 0), 20)
        XCTAssertEqual(PNGFilter.paeth(100, 50, 100), 50)
    }
}
