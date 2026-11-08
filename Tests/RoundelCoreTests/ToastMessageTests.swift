import XCTest
@testable import RoundelCore

/// A toast has a title and, when there is more to say, a smaller secondary line. Existing one-line messages are split
/// by a pure function, so nothing that produces messages had to change.
final class ToastMessageTests: XCTestCase {
    private func parse(_ text: String, _ kind: ToastKind = .error) -> ToastMessage { ToastMessage.parse(text, kind: kind) }

    func testAShortMessageIsJustATitle() {
        let m = parse("Converted wide.png → wide.jpg", .success)
        XCTAssertEqual(m.title, "Converted wide.png → wide.jpg")
        XCTAssertNil(m.detail)
        XCTAssertEqual(m.kind, .success)
    }

    func testTheActionNamePrefixIsDropped() {
        let m = parse("Convert Image: Couldn’t convert wide.png (too large for WebP (max 16383 pixels per side))")
        XCTAssertEqual(m.title, "Couldn’t convert wide.png")
        XCTAssertEqual(m.detail, "too large for WebP (max 16383 pixels per side)")
    }

    func testOtherActionPrefixesGoToo() {
        XCTAssertEqual(parse("Fix Layout: No letters to convert").title, "No letters to convert")
        XCTAssertEqual(parse("Open App: application “Nope” not found").title, "Application “Nope” not found", "and the first letter is capitalized")
        XCTAssertEqual(parse("Caffeinate: no power assertion").title, "No power assertion")
    }

    func testASentenceThatMerelyLooksLikeAPrefixStays() {
        XCTAssertEqual(parse("Couldn’t convert 2 files: a.txt (not an image), b.txt (can’t be read)").title, "Couldn’t convert 2 files")
        XCTAssertEqual(parse("Text fixed, but the layout was not switched: input source “Ukrainian-PC” is not enabled").title, "Text fixed, but the layout was not switched")
    }

    func testAShortLowercaseLeadInIsNotMistakenForAnActionName() {
        // Two or three words before a colon, but not capitalized action names: it is the sentence's own title.
        XCTAssertEqual(parse("Disk full: free some space").title, "Disk full")
        XCTAssertEqual(parse("Disk full: free some space").detail, "free some space")
        XCTAssertEqual(parse("File 2: not an image").title, "File 2", "digits are not an action name either")
    }

    func testABatchSummarySplitsIntoATitleAndOneLinePerRemainingFact() {
        let m = parse("Converted 8 files to JPEG · 2 skipped (already JPEG) · 1 failed: a.png (not an image)", .warning)
        XCTAssertEqual(m.title, "Converted 8 files to JPEG")
        XCTAssertEqual(m.detail, "2 skipped (already JPEG)\n1 failed: a.png (not an image)")
        XCTAssertEqual(m.kind, .warning)
    }

    func testTheSummaryOfTheReportedCase() {
        let m = parse("Converted 5 of 6 files to WebP · 1 failed: wide.png (too large for WebP (max 16383 pixels per side))", .warning)
        XCTAssertEqual(m.title, "Converted 5 of 6 files to WebP")
        XCTAssertEqual(m.detail, "1 failed: wide.png (too large for WebP (max 16383 pixels per side))")
    }

    func testAListOfFailuresAfterAColon() {
        let m = parse("Convert Image: Couldn’t convert 2 files: a.txt (not an image), b.txt (can’t be read)")
        XCTAssertEqual(m.title, "Couldn’t convert 2 files")
        XCTAssertEqual(m.detail, "a.txt (not an image), b.txt (can’t be read)")
    }

    func testTheFirstSentenceIsTheTitleAndTheRestIsDetail() {
        let m = parse("Config loaded with 13 warnings. Details: Console.app, search “app.roundel”.")
        XCTAssertEqual(m.title, "Config loaded with 13 warnings")
        XCTAssertEqual(m.detail, "Details: Console.app, search “app.roundel”.")
        let p = parse("Caffeinate needs the Accessibility permission. Allow Roundel in System Settings → Privacy & Security, then try again.")
        XCTAssertEqual(p.title, "Caffeinate needs the Accessibility permission")
        XCTAssertEqual(p.detail, "Allow Roundel in System Settings → Privacy & Security, then try again.")
    }

    func testATrailingParentheticalBecomesTheSecondaryLine() {
        let m = parse("Caffeinate on for 30 min (keeps the display awake)", .success)
        XCTAssertEqual(m.title, "Caffeinate on for 30 min")
        XCTAssertEqual(m.detail, "keeps the display awake")
    }

    func testParenthesesInTheMiddleAreLeftAlone() {
        let m = parse("Converted a (copy).png → a (copy).jpg", .success)
        XCTAssertEqual(m.title, "Converted a (copy).png → a (copy).jpg")
        XCTAssertNil(m.detail)
    }

    func testUnbalancedParenthesesAreLeftAlone() {
        XCTAssertNil(parse("Oops (this never closes").detail)
        XCTAssertNil(parse("Oops (a (b)").detail, "the closing parenthesis does not match the opening one")
    }

    func testAMultiLineMessageUsesTheFirstLineAsTheTitle() {
        let m = parse("Script failed\nexit status 1\nsee the log")
        XCTAssertEqual(m.title, "Script failed")
        XCTAssertEqual(m.detail, "exit status 1\nsee the log")
    }

    func testTheTitleIsNeverEmpty() {
        XCTAssertEqual(parse("", .success).title, "Done")
        XCTAssertEqual(parse("   ", .error).title, "Something went wrong")
        XCTAssertNil(parse("", .success).detail)
        XCTAssertEqual(parse(": just a colon", .error).title, ": just a colon", "nothing before the colon: keep the text")
    }

    func testAbsurdlyLongDetailIsShortened() {
        let m = parse("Failed · " + String(repeating: "x", count: 2000))
        XCTAssertLessThanOrEqual((m.detail ?? "").count, DesignMetrics.standard.toastMaxCharacters + 1)
        XCTAssertTrue((m.detail ?? "").hasSuffix("…"))
        XCTAssertEqual(m.title, "Failed")
    }

    func testTheKindIsKept() {
        for kind in [ToastKind.success, .warning, .error, .progress] { XCTAssertEqual(parse("Hello", kind).kind, kind) }
    }

    func testTheOldBooleanMapsToAKind() {
        XCTAssertEqual(ToastKind(isError: true), .error)
        XCTAssertEqual(ToastKind(isError: false), .success)
        XCTAssertTrue(ToastKind.error.isErrorStyle)
        XCTAssertTrue(ToastKind.warning.isErrorStyle)
        XCTAssertFalse(ToastKind.success.isErrorStyle)
        XCTAssertFalse(ToastKind.progress.isErrorStyle)
    }
}
