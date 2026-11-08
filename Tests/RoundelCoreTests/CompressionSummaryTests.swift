import XCTest
@testable import RoundelCore

final class CompressionSummaryTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/pics/\(name)") }
    private func done(_ name: String, before: Int, after: Int) -> CompressionItemResult {
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        return .compressed(source: url(name), output: url("\(stem) compressed.\(ext)"), bytesBefore: before, bytesAfter: after)
    }
    private func summary(_ results: [CompressionItemResult]) -> CompressionSummary { CompressionSummary(results: results) }

    func testABatchSaysHowManyHowMuchAndTheTotals() {
        let results = (1...5).map { done("p\($0).jpg", before: 3_680_000, after: 1_380_000) }
        XCTAssertEqual(summary(results).message, "Compressed 5 files, saved 62% (18.4 MB → 6.9 MB)")
    }

    func testOneFileNamesItsOutput() {
        XCTAssertEqual(summary([done("photo.jpg", before: 2_000_000, after: 1_000_000)]).message,
                       "Compressed photo.jpg → photo compressed.jpg, saved 50% (2.0 MB → 1.0 MB)")
    }

    func testTotalsCountOnlyWhatWasCompressed() {
        let results = [done("a.jpg", before: 1_000_000, after: 500_000), .alreadyOptimal(source: url("b.jpg")), .failed(source: url("c.jpg"), message: "x")]
        let s = summary(results)
        XCTAssertEqual(s.bytesBefore, 1_000_000)
        XCTAssertEqual(s.bytesAfter, 500_000)
        XCTAssertEqual(s.savedPercent, 50)
    }

    func testAlreadyOptimalSkippedAndFailedFilesAreMentionedWithTheirReasons() {
        let results: [CompressionItemResult] = [
            done("a.jpg", before: 1_000_000, after: 400_000), done("b.jpg", before: 1_000_000, after: 400_000),
            .alreadyOptimal(source: url("c.png")), .alreadyOptimal(source: url("d.png")),
            .skipped(source: url("e.gif"), reason: .useConvert("GIF")),
            .failed(source: url("f.png"), message: "damaged or incomplete"),
        ]
        XCTAssertEqual(summary(results).message,
                       "Compressed 2 of 3 files, saved 60% (2.0 MB → 800 KB) · 2 already optimal · e.gif: GIF isn’t compressed; use Convert to WebP · 1 failed: f.png (damaged or incomplete)")
    }

    func testManyFailuresAreListedUpToThreeThenCounted() {
        let results = [done("a.jpg", before: 1000, after: 500)] + (1...5).map { .failed(source: url("f\($0).png"), message: "can’t be read") }
        XCTAssertEqual(summary(results).message, "Compressed 1 of 6 files, saved 50% (1 KB → 500 bytes) · 5 failed: f1.png (can’t be read), f2.png (can’t be read), f3.png (can’t be read) and 2 more")
    }

    func testNothingCompressed() {
        XCTAssertEqual(summary([.alreadyOptimal(source: url("a.jpg"))]).message, "a.jpg is already optimal")
        XCTAssertEqual(summary([.alreadyOptimal(source: url("a.jpg")), .alreadyOptimal(source: url("b.jpg"))]).message, "Nothing to compress: 2 files already optimal")
        XCTAssertEqual(summary([.skipped(source: url("a.gif"), reason: .animated)]).message, "Nothing to compress · a.gif: animated, skipped (compressing would drop the animation)")
        XCTAssertEqual(summary([.alreadyOptimal(source: url("a.jpg")), .skipped(source: url("b.gif"), reason: .useConvert("GIF"))]).message,
                       "Nothing to compress: 1 already optimal · b.gif: GIF isn’t compressed; use Convert to WebP")
        XCTAssertEqual(summary([]).message, "No files to compress")
    }

    func testSeveralSkippedFilesAreNamedUpToThreeThenCounted() {
        let results = (1...5).map { CompressionItemResult.skipped(source: url("g\($0).gif"), reason: .useConvert("GIF")) }
        let text = summary(results).message
        XCTAssertTrue(text.hasPrefix("Nothing to compress · g1.gif: GIF isn’t compressed; use Convert to WebP · g2.gif"), text)
        XCTAssertTrue(text.hasSuffix("and 2 more skipped"), text)
    }

    func testWarningAndTotalFailure() {
        XCTAssertTrue(summary([done("a.jpg", before: 100, after: 50), .failed(source: url("b"), message: "x")]).isWarning)
        XCTAssertFalse(summary([done("a.jpg", before: 100, after: 50)]).isWarning)
        XCTAssertFalse(summary([.alreadyOptimal(source: url("a.jpg")), .skipped(source: url("b.gif"), reason: .animated)]).isWarning, "nothing went wrong")
        XCTAssertTrue(summary([.failed(source: url("b"), message: "x")]).isTotalFailure)
        XCTAssertTrue(summary([.alreadyOptimal(source: url("a")), .failed(source: url("b"), message: "x")]).isTotalFailure, "something failed and nothing was compressed")
        XCTAssertFalse(summary([done("a.jpg", before: 100, after: 50), .failed(source: url("b"), message: "x")]).isTotalFailure)
    }

    func testTheFailureTextWhenNothingWorked() {
        XCTAssertEqual(summary([.failed(source: url("a.png"), message: "damaged or incomplete")]).failureText, "Couldn’t compress a.png (damaged or incomplete)")
        XCTAssertEqual(summary([.failed(source: url("a.png"), message: "x"), .failed(source: url("b.png"), message: "")]).failureText, "Couldn’t compress 2 files: a.png (x), b.png (unknown error)")
    }

    func testTheProgressText() {
        XCTAssertEqual(CompressionSummary.progressMessage(done: 3, total: 10), "Compressing 3/10")
    }
}
