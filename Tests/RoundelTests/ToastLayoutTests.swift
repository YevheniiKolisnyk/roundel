import XCTest
import AppKit
@testable import Roundel

/// A toast that has no area is invisible: the window is "on screen" and the user sees nothing, whatever the message
/// says. Nothing here shows a window; it only measures what would be shown.
@MainActor
final class ToastLayoutTests: XCTestCase {
    private let short = "Converted wide.png → wide.jpg"
    private let webpError = "Convert Image: Couldn’t convert wide.png (too large for WebP (max 16383 pixels per side))"
    private let summary = "Converted 5 of 6 files to WebP · 1 failed: wide.png (too large for WebP (max 16383 pixels per side))"

    func testEveryToastHasAnAreaToBeDrawnIn() {
        for (message, isError) in [(short, false), (webpError, true), (summary, true), ("x", false), ("", true)] {
            let content = ToastLayout.content(for: message, isError: isError)
            XCTAssertGreaterThan(content.size.width, 0, message)
            XCTAssertGreaterThan(content.size.height, 0, message)
            XCTAssertEqual(content.view.frame.size, content.size, "the view fills exactly the area the window will have: \(message)")
        }
    }

    func testAToastNeverGetsWiderThanTheMaximum() {
        for message in [short, webpError, summary, String(repeating: "wide ", count: 200)] {
            XCTAssertLessThanOrEqual(ToastLayout.content(for: message, isError: true).size.width, ToastLayout.maxWidth, message)
        }
    }

    func testALongMessageWrapsInsteadOfBeingCutOffAfterTheFirstLine() {
        let one = ToastLayout.content(for: short, isError: false).size
        let wrapped = ToastLayout.content(for: summary, isError: true).size
        XCTAssertGreaterThan(wrapped.height, one.height + 10, "the reason at the end of the sentence must stay visible: \(wrapped) vs \(one)")
    }

    func testAShortMessageIsNarrowerThanALongOne() {
        XCTAssertLessThan(ToastLayout.content(for: "OK", isError: false).size.width, ToastLayout.content(for: webpError, isError: true).size.width)
    }

    func testAbsurdlyLongTextIsShortenedSoTheToastStaysOnScreen() {
        let text = String(repeating: "very long ", count: 500)
        XCTAssertLessThanOrEqual(ToastLayout.limited(text).count, ToastLayout.maxCharacters + 1)
        XCTAssertTrue(ToastLayout.limited(text).hasSuffix("…"))
        XCTAssertEqual(ToastLayout.limited(short), short, "normal messages are untouched")
        XCTAssertLessThan(ToastLayout.content(for: text, isError: true).size.height, 400)
    }

    func testASizeThatCannotBeUsedFallsBackToAVisibleOne() {
        for bad in [NSSize.zero, NSSize(width: 100, height: 0), NSSize(width: CGFloat.nan, height: 20), NSSize(width: 50, height: CGFloat.infinity)] {
            let fixed = ToastLayout.usable(bad)
            XCTAssertGreaterThan(fixed.width, 0)
            XCTAssertGreaterThan(fixed.height, 0)
            XCTAssertTrue(fixed.width.isFinite && fixed.height.isFinite)
        }
        XCTAssertEqual(ToastLayout.usable(NSSize(width: 200, height: 33)), NSSize(width: 200, height: 33))
    }

    func testTheToastSitsInTheTopRightCornerOfTheScreensUsableArea() {
        let screen = NSRect(x: 100, y: 50, width: 1440, height: 850)
        let size = NSSize(width: 300, height: 40)
        let origin = ToastLayout.origin(for: size, in: screen)
        XCTAssertEqual(origin.x, screen.maxX - 300 - ToastLayout.margin)
        XCTAssertEqual(origin.y, screen.maxY - 40 - ToastLayout.margin)
        XCTAssertTrue(screen.contains(NSRect(origin: origin, size: size)))
    }
}
