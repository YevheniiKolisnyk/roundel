import XCTest
@testable import RoundelCore

final class ByteSizeTests: XCTestCase {
    func testSizesAreShownTheWayFinderShowsThem() {
        XCTAssertEqual(ByteSize.format(0), "0 bytes")
        XCTAssertEqual(ByteSize.format(1), "1 byte")
        XCTAssertEqual(ByteSize.format(999), "999 bytes")
        XCTAssertEqual(ByteSize.format(1_000), "1 KB")
        XCTAssertEqual(ByteSize.format(1_499), "1 KB")
        XCTAssertEqual(ByteSize.format(512_000), "512 KB")
        XCTAssertEqual(ByteSize.format(999_999), "1.0 MB")
        XCTAssertEqual(ByteSize.format(18_400_000), "18.4 MB")
        XCTAssertEqual(ByteSize.format(6_940_000), "6.9 MB")
        XCTAssertEqual(ByteSize.format(1_230_000_000), "1.23 GB")
    }

    func testSavedPercentIsRoundedDownSoItNeverClaimsMoreThanItSaved() {
        XCTAssertEqual(ByteSize.savedPercent(before: 18_400_000, after: 6_900_000), 62, "62.5% is told as 62%")
        XCTAssertEqual(ByteSize.savedPercent(before: 1000, after: 900), 10)
        XCTAssertEqual(ByteSize.savedPercent(before: 1000, after: 981), 1, "1.9% is told as 1%, not 2%")
        XCTAssertEqual(ByteSize.savedPercent(before: 0, after: 0), 0)
        XCTAssertEqual(ByteSize.savedPercent(before: 100, after: 120), 0, "no negative savings")
    }
}
