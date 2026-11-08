import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

final class JPEGQualityTests: XCTestCase {
    private func jpeg(quality: Double?) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        var noise = TestNoise(state: 3)
        for i in 0..<48 {
            context.setFillColor(red: CGFloat(noise.next() % 256) / 255, green: CGFloat(i) / 48, blue: CGFloat(noise.next() % 256) / 255, alpha: 1)
            context.fill(CGRect(x: (i % 8) * 12, y: (i / 8) * 16, width: 12, height: 16))
        }
        let data = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, try XCTUnwrap(context.makeImage()), quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary } ?? nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return data as Data
    }

    func testTheConstants() {
        XCTAssertEqual(JPEGQuality.safetyMargin, 4)
        XCTAssertEqual(JPEGQuality.lowestWorthRecompressing, 46)
    }

    func testTheMeasuredScaleOfImageIOQualities() {
        // Measured from files ImageIO wrote at these qualities (IJG-scale quality read back from their quantization tables).
        let measured: [(Double, Double)] = [(1.0, 100), (0.9, 96), (0.8, 94), (0.7, 92), (0.6, 87), (0.5, 80), (0.4, 67), (0.3, 46), (0.2, 31), (0.1, 25)]
        for (q, ijg) in measured { XCTAssertEqual(JPEGQuality.ijg(forImageIO: q), ijg, accuracy: 0.51, "ImageIO \(q)") }
    }

    func testTheScaleIsMonotonicAndTheInverseUndoesIt() {
        var last = -1.0
        for q in stride(from: 0.0, through: 1.0, by: 0.01) {
            let ijg = JPEGQuality.ijg(forImageIO: q)
            XCTAssertGreaterThanOrEqual(ijg, last, "q \(q)")
            last = ijg
        }
        for ijg in stride(from: 30.0, through: 94.0, by: 2.0) {
            XCTAssertLessThanOrEqual(JPEGQuality.ijg(forImageIO: JPEGQuality.imageIO(forIJG: ijg)), ijg + 0.01, "never above what was asked")
            XCTAssertGreaterThan(JPEGQuality.ijg(forImageIO: JPEGQuality.imageIO(forIJG: ijg)), ijg - 3, "and close to it: \(ijg)")
        }
    }

    func testTheEstimateReadFromRealFilesMatchesTheirQuality() throws {
        for q in [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3] {
            let estimate = try XCTUnwrap(JPEGQuality.estimateIJG(from: jpeg(quality: q)), "q \(q)")
            XCTAssertEqual(Double(estimate), JPEGQuality.ijg(forImageIO: q), accuracy: 2.5, "ImageIO \(q)")
        }
    }

    func testBetterQualityMeansAHigherEstimate() throws {
        let low = try XCTUnwrap(JPEGQuality.estimateIJG(from: jpeg(quality: 0.4)))
        let high = try XCTUnwrap(JPEGQuality.estimateIJG(from: jpeg(quality: 0.9)))
        XCTAssertGreaterThan(high, low)
    }

    func testNoEstimateForAnythingThatIsNotAJPEGWithATable() {
        XCTAssertNil(JPEGQuality.estimateIJG(from: Data()))
        XCTAssertNil(JPEGQuality.estimateIJG(from: Data("hello".utf8)))
        XCTAssertNil(JPEGQuality.estimateIJG(from: Data([0xFF, 0xD8, 0xFF, 0xD9])))
        XCTAssertNil(JPEGQuality.estimateIJG(from: Data([0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x05, 0x00, 1, 2])), "a cut-off table")
    }

    func testTheCapForASource() throws {
        let high = try XCTUnwrap(JPEGQuality.cap(forSourceIJG: 96))
        XCTAssertEqual(JPEGQuality.ijg(forImageIO: high), 96 - Double(JPEGQuality.safetyMargin), accuracy: 2.5)
        XCTAssertLessThan(try XCTUnwrap(JPEGQuality.cap(forSourceIJG: 70)), high)
        XCTAssertNil(JPEGQuality.cap(forSourceIJG: Int(JPEGQuality.lowestWorthRecompressing) + JPEGQuality.safetyMargin - 1), "no room left")
        XCTAssertNotNil(JPEGQuality.cap(forSourceIJG: Int(JPEGQuality.lowestWorthRecompressing) + JPEGQuality.safetyMargin))
    }
}
