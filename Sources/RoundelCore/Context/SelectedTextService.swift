import Foundation

/// How long the service waits for each step. One place for every number, like `RingMetrics`.
public struct SelectedTextTiming: Equatable, Sendable {
    public var pollInterval: TimeInterval
    /// How long to wait for the pasteboard to change after Cmd+C. Nothing selected = nothing changes.
    public var copyTimeout: TimeInterval
    /// After the pasteboard changed, how long it must stay quiet before it is read (some apps clear, then write).
    public var settleInterval: TimeInterval
    /// How long to wait for Option/Command/Control/Shift to be released before posting a keystroke anyway.
    public var modifierTimeout: TimeInterval
    /// After Cmd+V: the earliest the original clipboard may come back.
    public var pasteMinWait: TimeInterval
    /// After the pasting app read the text: how long to wait before restoring (it may read more than once).
    public var pasteReadGrace: TimeInterval
    /// After Cmd+V: restore at this point even if the text was never read (paste failed or the app is very slow).
    public var pasteMaxWait: TimeInterval
    /// Bigger clipboards are not preserved, so the action does not run.
    public var snapshotLimitBytes: Int

    public static let standard = SelectedTextTiming(
        pollInterval: 0.01, copyTimeout: 0.5, settleInterval: 0.03, modifierTimeout: 1.0,
        pasteMinWait: 0.06, pasteReadGrace: 0.08, pasteMaxWait: 1.5, snapshotLimitBytes: 32 * 1024 * 1024
    )
}

/// What the text actions need from the outside world.
@MainActor
public protocol SelectedTextServing {
    /// Reads the selection of the frontmost app, passes it to `transform` and pastes the result over the selection.
    /// Returns `false` when the result equals the selection and nothing was pasted. The clipboard is the same
    /// afterwards. Throws an `ActionError` with a message for the user when nothing could be done.
    func transformSelection(_ transform: (String) throws -> String) async throws -> Bool
    /// Pastes the clipboard's text without its formatting, then puts the original clipboard back.
    func pastePlainClipboard() async throws
}

/// Selected-text capture and replacement through the pasteboard. Save everything, copy, read, restore; paste with a
/// temporary text, restore. One operation at a time, because a second snapshot taken in the middle of the first would
/// capture the temporary content and lose the user's clipboard for good.
@MainActor
public final class SelectedTextService: SelectedTextServing {
    private let pasteboard: any PasteboardAccessing
    private let keys: any KeystrokeSending
    private let modifiers: any ModifierKeyWatching
    private let secureInput: any SecureInputChecking
    private let clock: any AsyncClock
    private let timing: SelectedTextTiming
    private var isBusy = false

    public init(pasteboard: any PasteboardAccessing, keys: any KeystrokeSending, modifiers: any ModifierKeyWatching,
                secureInput: any SecureInputChecking, clock: any AsyncClock, timing: SelectedTextTiming = .standard) {
        self.pasteboard = pasteboard
        self.keys = keys
        self.modifiers = modifiers
        self.secureInput = secureInput
        self.clock = clock
        self.timing = timing
    }

    // MARK: SelectedTextServing

    public func transformSelection(_ transform: (String) throws -> String) async throws -> Bool {
        try begin()
        defer { isBusy = false }

        guard !secureInput.isSecureInputEnabled else {
            throw ActionError.failed("Secure input is on (a password field?), so the selection can’t be read")
        }
        let text = try await captureSelection()
        let result = try transform(text)
        guard result != text else { return false }
        try await paste(result, preserving: try takeSnapshot())
        return true
    }

    public func pastePlainClipboard() async throws {
        try begin()
        defer { isBusy = false }

        let snapshot = try takeSnapshot()
        guard let text = pasteboard.plainString(), !text.isEmpty else { throw ActionError.failed("The clipboard has no text") }
        try await paste(text, preserving: snapshot)
    }

    // MARK: Capture

    private func captureSelection() async throws -> String {
        let snapshot = try takeSnapshot()
        await waitForModifiersReleased()
        try Task.checkCancellation()

        let before = pasteboard.changeCount
        await keys.send(.copy)

        // Wait for the pasteboard to change; if it never does, nothing was selected.
        let start = clock.now()
        while pasteboard.changeCount == before {
            if Task.isCancelled { throw CancellationError() }
            if clock.now() - start >= timing.copyTimeout { throw ActionError.failed("No text selected") }
            await clock.sleep(for: timing.pollInterval)
        }

        // Some apps clear the pasteboard and then write: read only once it has been quiet for a moment.
        var settled = pasteboard.changeCount
        while true {
            await clock.sleep(for: timing.settleInterval)
            let current = pasteboard.changeCount
            if current == settled || Task.isCancelled { break }
            settled = current
        }

        let text = pasteboard.plainString()
        // Put the original back, unless somebody else wrote in the meantime: that is newer than our snapshot.
        if pasteboard.changeCount == settled { pasteboard.write(PasteboardMarkers.applied(to: snapshot.items)) }
        try Task.checkCancellation()

        guard let text, !text.isEmpty else { throw ActionError.failed("The selection has no text") }
        return text
    }

    // MARK: Paste

    private func paste(_ text: String, preserving snapshot: PasteboardSnapshot) async throws {
        await waitForModifiersReleased()
        try Task.checkCancellation()

        let read = ReadFlag()
        let written = pasteboard.writeLazyText(text, markers: PasteboardMarkers.representations) { [clock] in
            if read.at == nil { read.at = clock.now() }
        }
        await keys.send(.paste)

        // Restore when the app has read the text (plus a grace period), not after a guessed delay. The minimum
        // wait covers readers that look at the text before the keystroke is handled; the maximum covers a paste
        // that never happens.
        let start = clock.now()
        while true {
            let elapsed = clock.now() - start
            if Task.isCancelled || elapsed >= timing.pasteMaxWait { break }
            if let readAt = read.at, elapsed >= timing.pasteMinWait, clock.now() - readAt >= timing.pasteReadGrace { break }
            await clock.sleep(for: timing.pollInterval)
        }

        if pasteboard.changeCount == written { pasteboard.write(PasteboardMarkers.applied(to: snapshot.items)) }
        try Task.checkCancellation()
    }

    // MARK: Helpers

    private func begin() throws {
        guard !isBusy else { throw ActionError.failed("Another text action is still running") }
        isBusy = true
    }

    private func takeSnapshot() throws -> PasteboardSnapshot {
        do {
            return try pasteboard.snapshot(limitBytes: timing.snapshotLimitBytes)
        } catch PasteboardSnapshotError.tooLarge {
            throw ActionError.failed("Clipboard too large to preserve")
        } catch {
            throw ActionError.failed("Couldn’t read the whole clipboard, so nothing was changed")
        }
    }

    /// Keys held from the hotkey would turn the synthetic Cmd+C into something else, so wait for them (briefly).
    private func waitForModifiersReleased() async {
        let start = clock.now()
        while modifiers.anyModifierHeld, clock.now() - start < timing.modifierTimeout, !Task.isCancelled {
            await clock.sleep(for: timing.pollInterval)
        }
    }

    private final class ReadFlag {
        var at: TimeInterval?
    }
}
