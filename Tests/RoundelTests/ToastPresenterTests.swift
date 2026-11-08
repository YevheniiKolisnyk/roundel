import XCTest
import AppKit
import RoundelCore
@testable import Roundel

/// The presenter wired to a real (but off-screen) window: where it puts the stack, what it keeps, when it goes. The
/// "screen" is an area far to the left of every display, so nothing appears on the real desktop, and no input is sent.
@MainActor
final class ToastPresenterTests: XCTestCase {
    private let m = DesignMetrics.standard
    private let area = NSRect(x: -9000, y: 0, width: 1440, height: 850)
    private var time: TimeInterval = 100
    private var presenter: ToastPresenter!

    override func setUp() async throws {
        time = 100
        presenter = ToastPresenter(clock: { [unowned self] in time }, areaProvider: { [area] in area })
    }

    private func visibleTitles() -> [String] { presenter.stackEntries.map(\.message.title) }

    // MARK: Showing

    func testAToastAppearsTopRightOfTheUsableAreaInAWindowThatCannotTakeFocus() throws {
        presenter.show("Converted wide.png → wide.jpg")
        let panel = try XCTUnwrap(presenter.panelForTesting)
        let size = ToastLayout.stackSize(cardHeights: [Double(ToastLayout.cardSize(for: ToastMessage.parse("Converted wide.png → wide.jpg", kind: .success)).height)], hasMore: false)
        XCTAssertEqual(panel.frame, ToastLayout.panelFrame(size: size, in: area))
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertLessThanOrEqual(panel.frame.maxY, area.maxY, "never into the menu bar")
    }

    func testTheWindowDoesNotSwallowClicksOutsideTheToastsBecauseItsMouseHandlingIsUntouched() throws {
        presenter.show("hello")
        // Assigning ignoresMouseEvents (even to false) turns clear pixels into a click-swallowing area; the default stays.
        XCTAssertFalse(try XCTUnwrap(presenter.panelForTesting).ignoresMouseEvents)
    }

    func testOnlyTheNewestThreeAreShownAndTheRestAreCounted() throws {
        for title in ["one", "two", "three", "four", "five"] { presenter.show(title) }
        XCTAssertEqual(visibleTitles(), ["five", "four", "three"])
        XCTAssertEqual(presenter.stackHiddenCount, 2)
        let cards = presenter.stackEntries.map { Double(ToastLayout.cardSize(for: $0.message).height) }
        XCTAssertEqual(try XCTUnwrap(presenter.panelForTesting).frame.size, ToastLayout.stackSize(cardHeights: cards, hasMore: true))
    }

    func testAProgressToastIsUpdatedInPlaceAndReplacedByTheResult() {
        presenter.showProgress("Converting 1/3")
        presenter.showProgress("Converting 2/3")
        XCTAssertEqual(visibleTitles(), ["Converting 2/3"])
        presenter.show("Converted 3 files to WebP")
        XCTAssertEqual(visibleTitles(), ["Converted 3 files to WebP"])
    }

    func testAnErrorIsSplitIntoATitleAndASecondaryLine() {
        presenter.show("Convert Image: Couldn’t convert wide.png (too large for WebP (max 16383 pixels per side))", isError: true)
        XCTAssertEqual(visibleTitles(), ["Couldn’t convert wide.png"])
        XCTAssertEqual(presenter.stackEntries.first?.message.detail, "too large for WebP (max 16383 pixels per side)")
        XCTAssertEqual(presenter.stackEntries.first?.message.kind, .error)
    }

    // MARK: Leaving

    func testAToastLeavesWhenItsTimeIsUpAndTheWindowGoesAway() async throws {
        presenter.show("bye")
        time += 3.5
        presenter.refresh()
        XCTAssertEqual(visibleTitles(), [])
        try await Task.sleep(for: .milliseconds(700))   // the exit animation, then the window
        XCTAssertFalse(try XCTUnwrap(presenter.panelForTesting).isVisible)
    }

    func testNothingLeavesWhileThePointerIsOverTheStack() {
        presenter.show("stay")
        time += 1
        presenter.hover(true)
        time += 100
        presenter.refresh()
        XCTAssertEqual(visibleTitles(), ["stay"], "paused under the pointer")
        presenter.hover(false)
        time += 1.5
        presenter.refresh()
        XCTAssertEqual(visibleTitles(), ["stay"], "2 s of its 3 were left")
        time += 1
        presenter.refresh()
        XCTAssertEqual(visibleTitles(), [])
    }

    func testTheToastThatIsPushedOutOfViewWaitsForItsTurn() {
        presenter.show("Convert Image: Couldn’t convert a.png (not an image)", isError: true)   // 6 s
        for title in ["x", "y", "z"] { presenter.show(title) }                                  // 3 s each, push it out of view
        XCTAssertEqual(presenter.stackHiddenCount, 1)
        time += 3.2
        presenter.refresh()
        XCTAssertEqual(visibleTitles(), ["Couldn’t convert a.png"], "it was not lost while it was hidden")
    }
}
