import XCTest
@testable import RoundelCore

final class ZlibTests: XCTestCase {
    private func sample(_ count: Int) -> [UInt8] {
        var state: UInt32 = 42
        return (0..<count).map { index in
            state = state &* 1_664_525 &+ 1_013_904_223
            return index % 3 == 0 ? UInt8(truncatingIfNeeded: state >> 24) : UInt8(index % 7)   // partly random, partly repetitive
        }
    }

    func testDeflateThenInflateGivesTheOriginalBackAtEveryLevelAndStrategy() throws {
        let data = sample(50_000)
        for level in [Int32(1), 6, 9] {
            for strategy in [Zlib.Strategy.standard, .filtered] {
                let packed = try XCTUnwrap(Zlib.deflate(data, level: level, strategy: strategy), "level \(level)")
                XCTAssertEqual(Zlib.inflate(packed, limit: 1 << 20), data, "level \(level) \(strategy)")
            }
        }
    }

    func testHigherLevelsAreNotBiggerOnRepetitiveData() throws {
        let data = [UInt8](repeating: 7, count: 100_000) + sample(5_000)
        let quick = try XCTUnwrap(Zlib.deflate(data, level: 1))
        let best = try XCTUnwrap(Zlib.deflate(data, level: 9))
        XCTAssertLessThanOrEqual(best.count, quick.count)
        XCTAssertLessThan(best.count, data.count / 10)
    }

    func testEmptyInputRoundTrips() throws {
        let packed = try XCTUnwrap(Zlib.deflate([], level: 6))
        XCTAssertEqual(Zlib.inflate(packed, limit: 10), [])
    }

    func testACorruptOrTruncatedStreamIsRefusedNotHalfRead() throws {
        let packed = try XCTUnwrap(Zlib.deflate(sample(20_000), level: 6))
        XCTAssertNil(Zlib.inflate(Array(packed.dropLast(5)), limit: 1 << 20), "truncated")
        var corrupt = packed
        corrupt[corrupt.count / 2] ^= 0xFF
        XCTAssertNil(Zlib.inflate(corrupt, limit: 1 << 20), "corrupt")
        XCTAssertNil(Zlib.inflate([1, 2, 3, 4], limit: 100), "not zlib at all")
    }

    func testInflateStopsAtTheSizeLimit() throws {
        let packed = try XCTUnwrap(Zlib.deflate([UInt8](repeating: 0, count: 1_000_000), level: 9))
        XCTAssertNil(Zlib.inflate(packed, limit: 1000), "a small file must not be allowed to balloon")
        XCTAssertEqual(Zlib.inflate(packed, limit: 1_000_000)?.count, 1_000_000)
    }

    func testCRC32OfTheStandardCheckString() {
        XCTAssertEqual(Zlib.crc32(Array("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(Zlib.crc32(Array("xx123456789yy".utf8)[2..<11]), 0xCBF43926)
    }
}
