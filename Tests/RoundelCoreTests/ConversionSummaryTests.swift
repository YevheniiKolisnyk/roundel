import XCTest
@testable import RoundelCore

final class ConversionSummaryTests: XCTestCase {
    private let jpeg = ImageFormats.format(forKey: "jpeg")!
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    private func converted(_ name: String, notes: [ConversionNote] = []) -> ConversionItemResult {
        .converted(source: url(name + ".png"), output: url(name + ".jpg"), notes: notes)
    }

    private func summary(_ results: [ConversionItemResult]) -> ConversionSummary { ConversionSummary(results: results, format: jpeg) }

    func testOneFileNamesTheResult() {
        let s = summary([converted("photo")])
        XCTAssertEqual(s.message, "Converted photo.png → photo.jpg")
        XCTAssertFalse(s.isWarning)
        XCTAssertFalse(s.isTotalFailure)
    }

    func testSeveralFilesAreCounted() {
        let s = summary((1...10).map { converted("p\($0)") })
        XCTAssertEqual(s.message, "Converted 10 files to JPEG")
        XCTAssertEqual(s.convertedCount, 10)
    }

    func testSkippedFilesAreMentioned() {
        let skipped = ConversionItemResult.skipped(source: url("x.jpg"), reason: .alreadyInFormat)
        let s = summary((1...8).map { converted("p\($0)") } + [skipped, skipped])
        XCTAssertEqual(s.message, "Converted 8 files to JPEG · 2 skipped (already JPEG)")
        XCTAssertFalse(s.isWarning)
        XCTAssertEqual(s.skippedCount, 2)
    }

    func testNothingToDoWhenEverythingIsAlreadyInTheFormat() {
        let skipped = ConversionItemResult.skipped(source: url("x.jpg"), reason: .alreadyInFormat)
        let s = summary([skipped, skipped])
        XCTAssertEqual(s.message, "Nothing to convert: already JPEG")
        XCTAssertFalse(s.isWarning)
        XCTAssertFalse(s.isTotalFailure)
    }

    func testFailuresMakeItAWarningAndNameTheFiles() {
        let failed = ConversionItemResult.failed(source: url("bad.png"), message: "not an image")
        let s = summary((1...9).map { converted("p\($0)") } + [failed])
        XCTAssertEqual(s.message, "Converted 9 of 10 files to JPEG · 1 failed: bad.png (not an image)")
        XCTAssertTrue(s.isWarning)
        XCTAssertEqual(s.failedCount, 1)
    }

    func testSkippedAndFailedTogether() {
        let failed = ConversionItemResult.failed(source: url("bad.png"), message: "can’t be read")
        let skipped = ConversionItemResult.skipped(source: url("x.jpg"), reason: .alreadyInFormat)
        let s = summary([converted("a"), converted("b"), skipped, failed])
        XCTAssertEqual(s.message, "Converted 2 of 3 files to JPEG · 1 skipped (already JPEG) · 1 failed: bad.png (can’t be read)")
    }

    func testOnlyTheFirstFewFailuresAreListed() {
        let failures = (1...5).map { ConversionItemResult.failed(source: url("f\($0).png"), message: "not an image") }
        let s = summary([converted("ok")] + failures)
        XCTAssertTrue(s.message.contains("5 failed: f1.png (not an image), f2.png (not an image), f3.png (not an image) and 2 more"), s.message)
    }

    func testEverythingFailingIsATotalFailure() {
        let s = summary([.failed(source: url("a.txt"), message: "not an image")])
        XCTAssertTrue(s.isTotalFailure)
        XCTAssertEqual(s.failureText, "Couldn’t convert a.txt (not an image)")
        let two = summary([.failed(source: url("a.txt"), message: "not an image"), .failed(source: url("b.txt"), message: "can’t be read")])
        XCTAssertEqual(two.failureText, "Couldn’t convert 2 files: a.txt (not an image), b.txt (can’t be read)")
    }

    func testSkippedPlusFailedWithNothingConvertedIsStillATotalFailure() {
        let s = summary([.skipped(source: url("x.jpg"), reason: .alreadyInFormat), .failed(source: url("a.txt"), message: "not an image")])
        XCTAssertTrue(s.isTotalFailure)
    }

    func testAnimatedInputIsSaidToBeFirstFrameOnly() {
        let s = summary([converted("photo", notes: [.firstFrameOnly])])
        XCTAssertEqual(s.message, "Converted photo.png → photo.jpg · photo.png is animated: only the first frame was converted")
        XCTAssertFalse(s.isWarning)
    }

    func testSeveralAnimatedFilesAreSummarized() {
        let s = summary([converted("a", notes: [.firstFrameOnly]), converted("b", notes: [.firstFrameOnly]), converted("c", notes: [.firstFrameOnly]), converted("d")])
        XCTAssertEqual(s.message, "Converted 4 files to JPEG · 3 animated files: only the first frame was converted")
    }

    // MARK: Metadata a format could not keep

    private var webp: ImageFormat { ImageFormats.format(forKey: "webp")! }

    func testOneFileThatLostMetadataSaysWhichAndWhere() {
        let s = ConversionSummary(results: [converted("photo", notes: [.metadataNotKept(["IPTC", "resolution"])])], format: webp)
        XCTAssertEqual(s.message, "Converted photo.png → photo.jpg · photo.png: IPTC and resolution not kept in WebP")
        XCTAssertFalse(s.isWarning, "losing metadata is information, not a failure")
    }

    func testASingleLossIsNamedPlainly() {
        let s = ConversionSummary(results: [converted("photo", notes: [.metadataNotKept(["IPTC"])])], format: webp)
        XCTAssertTrue(s.message.hasSuffix("photo.png: IPTC not kept in WebP"), s.message)
    }

    func testThreeLossesUseACommaAndAnd() {
        let s = ConversionSummary(results: [converted("photo", notes: [.metadataNotKept(["IPTC", "resolution", "16-bit color"])])], format: webp)
        XCTAssertTrue(s.message.hasSuffix("photo.png: IPTC, resolution and 16-bit color not kept in WebP"), s.message)
    }

    func testSeveralFilesShareOneLineWithTheUnionOfWhatWasLost() {
        let s = ConversionSummary(results: [converted("a", notes: [.metadataNotKept(["IPTC"])]), converted("b", notes: [.metadataNotKept(["resolution", "IPTC"])]), converted("c")], format: webp)
        XCTAssertEqual(s.message, "Converted 3 files to WebP · 2 files: IPTC, resolution not kept in WebP")
    }

    func testBothNotesAppearTogether() {
        let s = ConversionSummary(results: [converted("photo", notes: [.firstFrameOnly, .metadataNotKept(["IPTC"])])], format: webp)
        XCTAssertEqual(s.message, "Converted photo.png → photo.jpg · photo.png is animated: only the first frame was converted · photo.png: IPTC not kept in WebP")
    }

    func testAnEmptyLossListSaysNothing() {
        let s = ConversionSummary(results: [converted("photo", notes: [.metadataNotKept([])])], format: webp)
        XCTAssertEqual(s.message, "Converted photo.png → photo.jpg")
    }

    func testABlankFailureMessageIsNeverShownAsNothing() {
        let s = summary([converted("ok"), .failed(source: url("bad.png"), message: "  ")])
        XCTAssertTrue(s.message.contains("bad.png (unknown error)"), s.message)
        XCTAssertEqual(summary([.failed(source: url("bad.png"), message: "")]).failureText, "Couldn’t convert bad.png (unknown error)")
    }

    func testProgressText() {
        XCTAssertEqual(ConversionSummary.progressMessage(done: 4, total: 10), "Converting 4/10")
        XCTAssertEqual(ConversionSummary.progressMessage(done: 0, total: 10), "Converting 0/10")
    }

    func testEmptyResultsMeanNothingHappened() {
        let s = summary([])
        XCTAssertEqual(s.message, "No files to convert")
        XCTAssertFalse(s.isTotalFailure)
    }
}
