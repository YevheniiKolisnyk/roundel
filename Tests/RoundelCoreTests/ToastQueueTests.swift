import XCTest
@testable import RoundelCore

/// The stack of toasts as a pure state machine, with time passed in. Nothing here shows anything.
final class ToastQueueTests: XCTestCase {
    private func message(_ title: String, _ kind: ToastKind = .success, detail: String? = nil) -> ToastMessage {
        ToastMessage(kind: kind, title: title, detail: detail)
    }

    // MARK: How long a toast stays

    func testDurationsByKind() {
        XCTAssertEqual(ToastQueue.duration(for: message("ok", .success)), 3)
        XCTAssertEqual(ToastQueue.duration(for: message("careful", .warning)), 6)
        XCTAssertEqual(ToastQueue.duration(for: message("broken", .error)), 6)
        XCTAssertNil(ToastQueue.duration(for: message("Converting 3/10", .progress)), "progress stays until it is replaced")
    }

    func testLongTextStaysLongerButNotForever() {
        let medium = message("x", .success, detail: String(repeating: "a", count: 139))   // 140 characters: 80 over the 60 free ones
        XCTAssertEqual(ToastQueue.duration(for: medium) ?? 0, 3 + 80 * 0.04, accuracy: 1e-9)
        XCTAssertEqual(ToastQueue.duration(for: message("x", .error, detail: String(repeating: "a", count: 3000))), 10, "capped")
    }

    // MARK: Order and limits

    func testNewestComesFirstAndIdsGrow() {
        var queue = ToastQueue()
        let a = queue.push(message("A"), now: 0)
        let b = queue.push(message("B"), now: 0)
        XCTAssertLessThan(a, b)
        XCTAssertEqual(queue.visible.map(\.message.title), ["B", "A"])
    }

    func testOnlyTheNewestThreeAreVisibleAndTheRestAreCounted() {
        var queue = ToastQueue()
        for title in ["A", "B", "C", "D", "E"] { queue.push(message(title), now: 0) }
        XCTAssertEqual(queue.visible.map(\.message.title), ["E", "D", "C"])
        XCTAssertEqual(queue.hiddenCount, 2)
    }

    func testTheQueueDoesNotGrowWithoutLimit() {
        var queue = ToastQueue()
        for i in 0..<100 { queue.push(message("n\(i)"), now: 0) }
        XCTAssertLessThanOrEqual(queue.entries.count, 20)
        XCTAssertEqual(queue.visible.first?.message.title, "n99", "the oldest are the ones dropped")
    }

    // MARK: Time

    func testAToastLeavesWhenItsTimeIsUp() {
        var queue = ToastQueue()
        queue.push(message("A"), now: 10)
        queue.advance(to: 12.9)
        XCTAssertEqual(queue.visible.count, 1)
        queue.advance(to: 13.0)
        XCTAssertTrue(queue.entries.isEmpty)
    }

    func testEachToastHasItsOwnClock() {
        var queue = ToastQueue()
        queue.push(message("old"), now: 0)
        queue.push(message("new"), now: 2)
        queue.advance(to: 3.5)
        XCTAssertEqual(queue.visible.map(\.message.title), ["new"], "the first one was due at 3")
    }

    func testHiddenToastsDoNotLoseTimeWhileTheyAreHidden() {
        var queue = ToastQueue()
        queue.push(message("A", .error), now: 0)            // 6 s
        for title in ["B", "C", "D"] { queue.push(message(title), now: 1) }   // 3 s each; A is pushed out of view at t = 1
        XCTAssertEqual(queue.visible.map(\.message.title), ["D", "C", "B"])
        XCTAssertEqual(queue.hiddenCount, 1)

        queue.advance(to: 4.1)                               // B, C and D expire at t = 4
        XCTAssertEqual(queue.visible.map(\.message.title), ["A"])
        XCTAssertEqual(queue.visible.first?.remaining ?? 0, 5 - 0.1, accuracy: 1e-9, "5 s were left when it was hidden, then 0.1 s ran")
    }

    func testTimeGoingBackwardsIsIgnored() {
        var queue = ToastQueue()
        queue.push(message("A"), now: 10)
        queue.advance(to: 5)
        XCTAssertEqual(queue.visible.first?.remaining ?? 0, 3, accuracy: 1e-9)
    }

    func testTimeUntilTheNextExpiry() {
        var queue = ToastQueue()
        XCTAssertNil(queue.secondsUntilNextExpiry)
        queue.push(message("A", .error), now: 0)             // 6
        queue.push(message("B"), now: 1)                      // 3 -> due at 4
        XCTAssertEqual(queue.secondsUntilNextExpiry ?? 0, 3, accuracy: 1e-9)
        queue.advance(to: 2)
        XCTAssertEqual(queue.secondsUntilNextExpiry ?? 0, 2, accuracy: 1e-9)
    }

    // MARK: Hover pauses

    func testNothingExpiresWhilePaused() {
        var queue = ToastQueue()
        queue.push(message("A"), now: 0)
        queue.setPaused(true, now: 1)
        queue.advance(to: 100)
        XCTAssertEqual(queue.visible.count, 1)
        XCTAssertNil(queue.secondsUntilNextExpiry, "no timer is needed while paused")
        XCTAssertEqual(queue.visible.first?.remaining ?? 0, 2, accuracy: 1e-9, "the 1 s before the pause counted")
    }

    func testResumingContinuesWhereItStopped() {
        var queue = ToastQueue()
        queue.push(message("A"), now: 0)
        queue.setPaused(true, now: 1)
        queue.setPaused(false, now: 100)
        queue.advance(to: 101.5)
        XCTAssertEqual(queue.visible.count, 1)
        queue.advance(to: 102)
        XCTAssertTrue(queue.entries.isEmpty)
    }

    func testPausingTwiceOrResumingWithoutAPauseChangesNothing() {
        var queue = ToastQueue()
        queue.push(message("A"), now: 0)
        queue.setPaused(false, now: 1)
        queue.setPaused(true, now: 2)
        queue.setPaused(true, now: 50)
        queue.setPaused(false, now: 60)
        XCTAssertEqual(queue.visible.first?.remaining ?? 0, 1, accuracy: 1e-9)
    }

    func testANewToastWhilePausedStillStartsWithAFullClock() {
        var queue = ToastQueue()
        queue.setPaused(true, now: 0)
        queue.push(message("A"), now: 5)
        queue.advance(to: 50)
        XCTAssertEqual(queue.visible.first?.remaining ?? 0, 3, accuracy: 1e-9)
    }

    // MARK: Repeats, progress, dismissal

    func testTheSameMessageAgainRefreshesTheClockInsteadOfStacking() {
        var queue = ToastQueue()
        let first = queue.push(message("Same"), now: 0)
        queue.advance(to: 2)
        let again = queue.push(message("Same"), now: 2)
        XCTAssertEqual(first, again)
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertEqual(queue.visible.first?.remaining ?? 0, 3, accuracy: 1e-9)
    }

    func testProgressIsUpdatedInPlace() {
        var queue = ToastQueue()
        let first = queue.push(message("Converting 1/10", .progress), now: 0)
        let second = queue.push(message("Converting 2/10", .progress), now: 1)
        let third = queue.push(message("Converting 3/10", .progress), now: 2)
        XCTAssertEqual([first, second, third], [first, first, first], "same entry, new text")
        XCTAssertEqual(queue.entries.map(\.message.title), ["Converting 3/10"])
    }

    func testProgressNeverExpiresOnItsOwn() {
        var queue = ToastQueue()
        queue.push(message("Converting 1/10", .progress), now: 0)
        queue.advance(to: 10_000)
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertNil(queue.secondsUntilNextExpiry)
    }

    func testTheFinalMessageReplacesTheProgressItBelongsTo() {
        var queue = ToastQueue()
        queue.push(message("Converting 9/10", .progress), now: 0)
        queue.push(message("Converted 10 files to WebP"), now: 1)
        XCTAssertEqual(queue.entries.map(\.message.title), ["Converted 10 files to WebP"])
    }

    func testDismissRemovesOneToast() {
        var queue = ToastQueue()
        let a = queue.push(message("A"), now: 0)
        queue.push(message("B"), now: 0)
        queue.dismiss(id: a)
        XCTAssertEqual(queue.entries.map(\.message.title), ["B"])
        queue.dismiss(id: 999)
        XCTAssertEqual(queue.entries.count, 1)
    }

    func testAnEmptyQueueIsHarmless() {
        var queue = ToastQueue()
        queue.advance(to: 5)
        queue.setPaused(true, now: 6)
        queue.setPaused(false, now: 7)
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertEqual(queue.hiddenCount, 0)
    }
}
