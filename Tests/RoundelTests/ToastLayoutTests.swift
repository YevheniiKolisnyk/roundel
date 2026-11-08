import XCTest
import AppKit
import RoundelCore
@testable import Roundel

/// Sizes and positions of the toast stack. Nothing here shows a window; it only measures what would be shown.
@MainActor
final class ToastLayoutTests: XCTestCase {
    private let m = DesignMetrics.standard
    private func message(_ text: String, _ kind: ToastKind = .error) -> ToastMessage { ToastMessage.parse(text, kind: kind) }

    // MARK: A card

    func testEveryCardHasAnAreaAndTheAgreedWidth() {
        for text in ["Converted wide.png → wide.jpg", "Convert Image: Couldn’t convert wide.png (too large for WebP (max 16383 pixels per side))", "x", ""] {
            let size = ToastLayout.cardSize(for: message(text))
            XCTAssertEqual(size.width, m.toastWidth, text)
            XCTAssertGreaterThan(size.height, 0, text)
        }
    }

    func testALongerMessageGivesATallerCardInsteadOfBeingCutOff() {
        let short = ToastLayout.cardSize(for: message("Done", .success)).height
        let withDetail = ToastLayout.cardSize(for: message("Converted 5 of 6 files to WebP · 1 failed: wide.png (too large for WebP (max 16383 pixels per side))", .warning)).height
        let long = ToastLayout.cardSize(for: message("Couldn’t convert 14 files: " + String(repeating: "IMG_0000.heic (not an image), ", count: 12))).height
        XCTAssertGreaterThan(withDetail, short + 10, "a secondary line takes room")
        XCTAssertGreaterThan(long, withDetail, "and so does a long one")
    }

    func testAnAbsurdlyLongMessageStaysBounded() {
        let size = ToastLayout.cardSize(for: message("Failed · " + String(repeating: "word ", count: 2000)))
        XCTAssertLessThan(size.height, 600)
    }

    func testASizeThatCannotBeUsedFallsBackToAVisibleOne() {
        for bad in [NSSize.zero, NSSize(width: 100, height: 0), NSSize(width: CGFloat.nan, height: 20), NSSize(width: 50, height: CGFloat.infinity)] {
            let fixed = ToastLayout.usable(bad)
            XCTAssertGreaterThan(fixed.width, 0)
            XCTAssertGreaterThan(fixed.height, 0)
            XCTAssertTrue(fixed.width.isFinite && fixed.height.isFinite)
        }
        XCTAssertEqual(ToastLayout.usable(NSSize(width: 360, height: 60)), NSSize(width: 360, height: 60))
    }

    // MARK: The stack

    func testTheStackIsAsWideAsACardPlusRoomForTheShadow() {
        let size = ToastLayout.stackSize(cardHeights: [60], hasMore: false)
        XCTAssertEqual(size.width, m.toastWidth + ToastLayout.insets.left + ToastLayout.insets.right)
    }

    func testTheStackHeightAddsCardsGapsInsetsAndTheMoreChip() {
        let insets = ToastLayout.insets
        let two = ToastLayout.stackSize(cardHeights: [60, 80], hasMore: false)
        XCTAssertEqual(two.height, insets.top + 60 + m.toastSpacing + 80 + insets.bottom)
        let withMore = ToastLayout.stackSize(cardHeights: [60, 80], hasMore: true)
        XCTAssertEqual(withMore.height, two.height + m.toastSpacing + m.toastMoreChipHeight)
    }

    func testAnEmptyStackHasNoSize() {
        XCTAssertEqual(ToastLayout.stackSize(cardHeights: [], hasMore: false), .zero)
    }

    // MARK: Placement

    func testTheFirstCardSitsATopRightMarginBelowTheMenuBar() {
        let area = NSRect(x: 100, y: 50, width: 1440, height: 850)   // the screen's usable area: the menu bar is above it
        let size = ToastLayout.stackSize(cardHeights: [70], hasMore: false)
        let frame = ToastLayout.panelFrame(size: size, in: area)
        let insets = ToastLayout.insets
        XCTAssertEqual(frame.maxX - insets.right, area.maxX - m.toastMargin, "card's right edge")
        XCTAssertEqual(frame.maxY - insets.top, area.maxY - m.toastMargin, "card's top edge")
        XCTAssertEqual(frame.size, size)
    }

    func testTheWindowNeverReachesIntoTheMenuBar() {
        let area = NSRect(x: 0, y: 0, width: 1728, height: 1079)
        for heights in [[40.0], [40, 90, 60], [200, 200, 200]] {
            let frame = ToastLayout.panelFrame(size: ToastLayout.stackSize(cardHeights: heights, hasMore: heights.count > 2), in: area)
            XCTAssertLessThanOrEqual(frame.maxY, area.maxY, "\(heights)")
        }
    }
}
