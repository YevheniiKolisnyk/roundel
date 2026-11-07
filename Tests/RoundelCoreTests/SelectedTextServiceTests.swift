import XCTest
@testable import RoundelCore

@MainActor
final class SelectedTextServiceTests: XCTestCase {
    private let timing = SelectedTextTiming.standard

    private func message(_ block: () async throws -> some Any) async -> String? {
        do { _ = try await block(); return nil } catch let error as ActionError { return error.message } catch { return "\(error)" }
    }

    // MARK: Snapshot and markers (pure)

    func testSnapshotCountsBytesOfEveryRepresentation() {
        let snapshot = PasteboardSnapshot(items: richClipboard())
        XCTAssertEqual(snapshot.byteCount, "old text{\\rtf1 old}customfile:///tmp/a.txtPNGDATA".utf8.count)
    }

    func testMarkersAreAddedToTheFirstItemOnlyAndOnlyOnce() {
        let marked = PasteboardMarkers.applied(to: richClipboard())
        XCTAssertEqual(Set(marked[0].representations.map(\.type)).intersection(PasteboardMarkers.types), PasteboardMarkers.types)
        XCTAssertTrue(marked[1].representations.map(\.type).allSatisfy { !PasteboardMarkers.types.contains($0) })
        XCTAssertEqual(PasteboardMarkers.applied(to: marked), marked, "idempotent")
        XCTAssertEqual(PasteboardMarkers.types, ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"])
    }

    func testMarkersOnAnEmptyClipboardChangeNothing() {
        XCTAssertEqual(PasteboardMarkers.applied(to: []), [])
    }

    // MARK: Capture

    func testCaptureReadsTheSelectionAndRestoresEveryItemAndType() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("selected")
        var captured: String?

        let replaced = try await env.service.transformSelection { captured = $0; return $0 }

        XCTAssertEqual(captured, "selected")
        XCTAssertFalse(replaced, "nothing changed, so nothing is pasted")
        XCTAssertEqual(env.keys.sent, [.copy])
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())
        XCTAssertTrue(env.pasteboard.writes.allSatisfy(\.hasMarkers), "temporary writes are marked for clipboard managers")
        XCTAssertEqual(env.pasteboard.writes.count, 1, "only the restore")
    }

    func testCaptureTakesTheSnapshotBeforeCopyingAndWithTheSizeLimit() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("x")
        _ = try await env.service.transformSelection { $0 }
        XCTAssertEqual(env.pasteboard.snapshotLimits.first, timing.snapshotLimitBytes)
    }

    func testCaptureWaitsForAnAppThatClearsAndThenWrites() async throws {
        let env = TextEnvironment(items: [item(rep(PasteboardTypes.string, "old"))])
        env.keys.onSend = { [pb = env.pasteboard, clock = env.clock] keystroke in
            guard keystroke == .copy else { return }
            clock.schedule(after: 0.005) { pb.externalClear() }
            clock.schedule(after: 0.02) { pb.externalCopy("final") }
        }
        var captured: String?
        _ = try await env.service.transformSelection { captured = $0; return $0 }
        XCTAssertEqual(captured, "final", "does not read the half-written state")
    }

    func testNoSelectionTimesOutAndLeavesTheClipboardUntouched() async {
        let env = TextEnvironment(items: richClipboard())
        let error = await message { try await env.service.transformSelection { $0 } }
        XCTAssertEqual(error, "No text selected")
        XCTAssertEqual(env.keys.sent, [.copy])
        XCTAssertEqual(env.pasteboard.items, richClipboard())
        XCTAssertTrue(env.pasteboard.writes.isEmpty, "nothing was written")
        XCTAssertGreaterThanOrEqual(env.clock.time, timing.copyTimeout)
    }

    func testSecureInputStopsBeforeAnythingHappens() async {
        let env = TextEnvironment(items: richClipboard())
        env.secure.isSecureInputEnabled = true
        let error = await message { try await env.service.transformSelection { $0 } }
        XCTAssertEqual(error, "Secure input is on (a password field?), so the selection can’t be read")
        XCTAssertTrue(env.keys.sent.isEmpty)
        XCTAssertTrue(env.pasteboard.writes.isEmpty)
        XCTAssertTrue(env.pasteboard.snapshotLimits.isEmpty)
    }

    func testClipboardTooLargeToPreserveAbortsWithoutTouchingIt() async {
        let env = TextEnvironment(items: richClipboard())
        env.pasteboard.snapshotError = .tooLarge
        let error = await message { try await env.service.transformSelection { $0 } }
        XCTAssertEqual(error, "Clipboard too large to preserve")
        XCTAssertTrue(env.keys.sent.isEmpty)
        XCTAssertTrue(env.pasteboard.writes.isEmpty)
    }

    func testIncompleteSnapshotAbortsWithoutTouchingTheClipboard() async {
        let env = TextEnvironment(items: richClipboard())
        env.pasteboard.snapshotError = .incomplete
        let error = await message { try await env.service.transformSelection { $0 } }
        XCTAssertEqual(error, "Couldn’t read the whole clipboard, so nothing was changed")
        XCTAssertTrue(env.keys.sent.isEmpty)
        XCTAssertTrue(env.pasteboard.writes.isEmpty)
    }

    func testASelectionWithoutTextIsReportedAndTheClipboardRestored() async {
        let env = TextEnvironment(items: richClipboard())
        env.keys.onSend = { [pb = env.pasteboard] keystroke in
            if keystroke == .copy { pb.externalReplace(with: [item(rep("public.png", "IMAGE"))]) }
        }
        let error = await message { try await env.service.transformSelection { $0 } }
        XCTAssertEqual(error, "The selection has no text")
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())
    }

    func testDoesNotRestoreOverSomethingTheUserCopiedMeanwhile() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("selected")
        env.pasteboard.afterPlainStringRead = { [pb = env.pasteboard] in pb.externalCopy("user copied this") }
        _ = try await env.service.transformSelection { $0 }
        XCTAssertEqual(env.pasteboard.plainString(), "user copied this")
        XCTAssertTrue(env.pasteboard.writes.isEmpty)
    }

    // MARK: Modifiers

    func testWaitsForModifiersToBeReleasedBeforeCopying() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("x")
        env.modifiers.heldChecks = 5
        _ = try await env.service.transformSelection { $0 }
        let sentAt = try XCTUnwrap(env.keys.sentAt.first)
        XCTAssertEqual(sentAt, 5 * timing.pollInterval, accuracy: 0.001)
    }

    func testGivesUpWaitingForModifiersAfterTheTimeoutAndStillCopies() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("x")
        env.modifiers.heldChecks = .max
        _ = try await env.service.transformSelection { $0 }
        let sentAt = try XCTUnwrap(env.keys.sentAt.first)
        XCTAssertEqual(sentAt, timing.modifierTimeout, accuracy: timing.pollInterval * 2)
        XCTAssertEqual(env.keys.sent, [.copy])
    }

    func testWaitsForModifiersBeforePastingToo() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("x")
        env.keys.onSend = { [pb = env.pasteboard, modifiers = env.modifiers, clock = env.clock] keystroke in
            if keystroke == .copy { pb.externalCopy("x"); modifiers.heldChecks = 0 }
            if keystroke == .paste { clock.schedule(after: 0.01) { pb.simulateAppRead() } }
        }
        env.modifiers.heldChecks = 0
        _ = try await env.service.transformSelection { _ in "y" }
        XCTAssertEqual(env.keys.sent, [.copy, .paste])
    }

    // MARK: Replace

    func testTransformPastesTheResultThenRestoresTheOriginalAfterTheAppReadIt() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.keys.onSend = { [pb = env.pasteboard, clock = env.clock] keystroke in
            switch keystroke {
            case .copy: pb.externalCopy("hello")
            case .paste: clock.schedule(after: 0.02) { pb.simulateAppRead() }
            }
        }

        let replaced = try await env.service.transformSelection { $0.uppercased() }

        XCTAssertTrue(replaced)
        XCTAssertEqual(env.keys.sent, [.copy, .paste])
        let textWrites = env.pasteboard.writes.filter { $0.kind == .lazyText }
        XCTAssertEqual(textWrites.map(\.text), ["HELLO"])
        XCTAssertTrue(textWrites.allSatisfy(\.hasMarkers))
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())

        let pasteAt = try XCTUnwrap(env.keys.sentAt.last)
        let restoreAt = try XCTUnwrap(env.pasteboard.writes.last?.time)
        XCTAssertGreaterThanOrEqual(restoreAt - pasteAt, 0.02 + timing.pasteReadGrace - 0.001, "grace period after the read")
        XCTAssertLessThan(restoreAt - pasteAt, 0.02 + timing.pasteReadGrace + 2 * timing.pollInterval)
    }

    func testRestoreNeverHappensBeforeTheMinimumWaitEvenIfTheReadWasInstant() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.keys.onSend = { [pb = env.pasteboard] keystroke in
            switch keystroke {
            case .copy: pb.externalCopy("hello")
            case .paste: pb.simulateAppRead()   // read right away, before the app could have used it
            }
        }
        _ = try await env.service.transformSelection { $0.uppercased() }
        let pasteAt = try XCTUnwrap(env.keys.sentAt.last)
        let restoreAt = try XCTUnwrap(env.pasteboard.writes.last?.time)
        XCTAssertGreaterThanOrEqual(restoreAt - pasteAt, timing.pasteMinWait - 0.001)
    }

    func testIfTheAppNeverReadsTheTextTheOriginalIsRestoredAtTheHardLimit() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("hello")
        _ = try await env.service.transformSelection { $0.uppercased() }
        let pasteAt = try XCTUnwrap(env.keys.sentAt.last)
        let restoreAt = try XCTUnwrap(env.pasteboard.writes.last?.time)
        XCTAssertEqual(restoreAt - pasteAt, timing.pasteMaxWait, accuracy: 2 * timing.pollInterval)
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())
    }

    func testDoesNotRestoreOverANewCopyMadeDuringThePaste() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.keys.onSend = { [pb = env.pasteboard, clock = env.clock] keystroke in
            switch keystroke {
            case .copy: pb.externalCopy("hello")
            case .paste:
                clock.schedule(after: 0.02) { pb.simulateAppRead() }
                clock.schedule(after: 0.04) { pb.externalCopy("copied meanwhile") }
            }
        }
        _ = try await env.service.transformSelection { $0.uppercased() }
        XCTAssertEqual(env.pasteboard.plainString(), "copied meanwhile")
    }

    func testAnUnchangedResultIsNotPasted() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("ALREADY UPPER")
        let replaced = try await env.service.transformSelection { $0.uppercased() }
        XCTAssertFalse(replaced)
        XCTAssertEqual(env.keys.sent, [.copy])
    }

    func testAFailingTransformPastesNothingAndLeavesTheClipboardRestored() async {
        struct Boom: Error {}
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("hello")
        do {
            _ = try await env.service.transformSelection { _ in throw ActionError.failed("nope") }
            XCTFail("expected a throw")
        } catch let error as ActionError {
            XCTAssertEqual(error.message, "nope")
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(env.keys.sent, [.copy])
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())
    }

    func testAnEmptyClipboardIsRestoredToEmpty() async throws {
        let env = TextEnvironment(items: [])
        env.keys.onSend = { [pb = env.pasteboard, clock = env.clock] keystroke in
            switch keystroke {
            case .copy: pb.externalCopy("hello")
            case .paste: clock.schedule(after: 0.01) { pb.simulateAppRead() }
            }
        }
        _ = try await env.service.transformSelection { $0.uppercased() }
        XCTAssertEqual(env.pasteboard.items, [])
    }

    // MARK: Single flight and cancellation

    func testASecondCallWhileOneIsRunningIsRejectedInsteadOfCorruptingTheSnapshot() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.clock.yieldOnSleep = true
        env.appCopies("x")

        let first = Task { @MainActor in try await env.service.transformSelection { $0 } }
        let second = Task { @MainActor in try await env.service.transformSelection { $0 } }

        let secondResult = await second.result
        let firstResult = await first.result
        guard case .failure(let error as ActionError) = secondResult else { return XCTFail("second call should fail: \(secondResult)") }
        XCTAssertEqual(error.message, "Another text action is still running")
        XCTAssertNoThrow(try firstResult.get())
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())

        // And the service is free again afterwards.
        env.appCopies("again")
        _ = try await env.service.transformSelection { $0 }
    }

    func testCancellationDuringThePasteStillRestoresTheClipboard() async {
        let env = TextEnvironment(items: richClipboard())
        env.appCopies("hello")
        var task: Task<Bool, Error>!
        task = Task { @MainActor in try await env.service.transformSelection { $0.uppercased() } }
        env.clock.onSleep = { [keys = env.keys] in
            if keys.sent.contains(.paste) { task.cancel() }
        }

        let result = await task.result
        guard case .failure(let error) = result else { return XCTFail("expected cancellation") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())
        XCTAssertLessThan(env.clock.time, timing.pasteMaxWait / 2, "restored promptly, not after the hard limit")
    }

    // MARK: Paste as plain text

    func testPastePlainPastesTheClipboardTextAndRestoresTheRichOriginal() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.keys.onSend = { [pb = env.pasteboard, clock = env.clock] keystroke in
            if keystroke == .paste { clock.schedule(after: 0.01) { pb.simulateAppRead() } }
        }
        try await env.service.pastePlainClipboard()

        XCTAssertEqual(env.keys.sent, [.paste], "no copy: nothing is captured")
        let textWrites = env.pasteboard.writes.filter { $0.kind == .lazyText }
        XCTAssertEqual(textWrites.map(\.text), ["old text"])
        XCTAssertTrue(textWrites.allSatisfy(\.hasMarkers))
        XCTAssertEqual(env.pasteboard.itemsWithoutMarkers, richClipboard())
    }

    func testPastePlainWithoutTextOnTheClipboardSaysSo() async {
        let env = TextEnvironment(items: [item(rep("public.png", "IMAGE"))])
        let error = await message { try await env.service.pastePlainClipboard() }
        XCTAssertEqual(error, "The clipboard has no text")
        XCTAssertTrue(env.keys.sent.isEmpty)
        XCTAssertTrue(env.pasteboard.writes.isEmpty)
    }

    func testPastePlainRefusesAClipboardItCannotPreserve() async {
        let env = TextEnvironment(items: richClipboard())
        env.pasteboard.snapshotError = .tooLarge
        let error = await message { try await env.service.pastePlainClipboard() }
        XCTAssertEqual(error, "Clipboard too large to preserve")
        XCTAssertTrue(env.keys.sent.isEmpty)
    }

    func testPastingIsNotBlockedBySecureInput() async throws {
        let env = TextEnvironment(items: richClipboard())
        env.secure.isSecureInputEnabled = true
        env.keys.onSend = { [pb = env.pasteboard, clock = env.clock] keystroke in
            if keystroke == .paste { clock.schedule(after: 0.01) { pb.simulateAppRead() } }
        }
        try await env.service.pastePlainClipboard()
        XCTAssertEqual(env.keys.sent, [.paste])
    }
}
