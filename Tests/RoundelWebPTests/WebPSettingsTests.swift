import XCTest
import RoundelCore
@testable import RoundelWebP

/// How the options become libwebp settings. Pure.
final class WebPSettingsTests: XCTestCase {
    func testLossyDefaultsToQuality80() {
        let settings = WebPSettings.make(from: ImageEncodingOptions())
        XCTAssertFalse(settings.lossless)
        XCTAssertEqual(settings.quality, 80)
    }

    func testLossyQualityIsAPercentage() {
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: 0.5)).quality, 50)
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: 1)).quality, 100)
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: 0)).quality, 0)
    }

    func testQualityIsClampedAndNonsenseFallsBackToTheDefault() {
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: 1.5)).quality, 100)
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: -3)).quality, 0)
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: .nan)).quality, 80)
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: .infinity)).quality, 80)
    }

    func testLosslessUsesQualityAsCompressionEffort() {
        let settings = WebPSettings.make(from: ImageEncodingOptions(quality: 1, lossless: true))
        XCTAssertTrue(settings.lossless)
        XCTAssertEqual(settings.quality, 100, "for lossless output libwebp reads 'quality' as how hard to try")
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(quality: 0.2, lossless: true)).quality, 20)
    }

    func testLosslessDefaultsToAModerateEffort() {
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(lossless: true)).quality, 75)
    }

    func testTheMethodIsTheBalancedOne() {
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions()).method, 4)
        XCTAssertEqual(WebPSettings.make(from: ImageEncodingOptions(lossless: true)).method, 4)
    }

    func testTheLargestSideWebpAllows() {
        XCTAssertEqual(WebPSettings.maxDimension, 16383)
    }
}
