import Foundation
@testable import RoundelCore

// Fakes for the selected-text service. No real pasteboard, keystroke or clock is ever touched.

/// Virtual time: `sleep` advances it instantly and runs the events scheduled for that moment.
@MainActor
final class FakeClock: AsyncClock {
    private(set) var time: TimeInterval = 0
    private var events: [(at: TimeInterval, action: @MainActor () -> Void)] = []
    var yieldOnSleep = false
    var onSleep: (@MainActor () -> Void)?

    func now() -> TimeInterval { time }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        events.append((time + delay, action))
    }

    func sleep(for seconds: TimeInterval) async {
        onSleep?()
        if yieldOnSleep { await Task.yield() }
        time += seconds
        let due = events.filter { $0.at <= time + 1e-9 }.sorted { $0.at < $1.at }
        events.removeAll { $0.at <= time + 1e-9 }
        for event in due { event.action() }
    }
}

@MainActor
final class FakePasteboard: PasteboardAccessing {
    struct Write {
        enum Kind { case items, lazyText }
        let kind: Kind
        let time: TimeInterval
        let text: String?
        let hasMarkers: Bool
    }

    private(set) var items: [PasteboardItemSnapshot]
    private(set) var changeCount = 1
    private(set) var writes: [Write] = []
    private var readHandler: (@MainActor () -> Void)?
    var snapshotError: PasteboardSnapshotError?
    var clock: FakeClock?
    var snapshotLimits: [Int] = []
    /// Runs once right after `plainString()` returns, e.g. to simulate the user copying something meanwhile.
    var afterPlainStringRead: (@MainActor () -> Void)?

    init(items: [PasteboardItemSnapshot] = []) { self.items = items }

    func snapshot(limitBytes: Int) throws -> PasteboardSnapshot {
        snapshotLimits.append(limitBytes)
        if let snapshotError { throw snapshotError }
        return PasteboardSnapshot(items: items)
    }

    func write(_ newItems: [PasteboardItemSnapshot]) -> Int {
        items = newItems
        changeCount += 1
        writes.append(Write(kind: .items, time: clock?.time ?? 0, text: nil, hasMarkers: Self.hasMarkers(newItems)))
        return changeCount
    }

    func writeLazyText(_ text: String, markers: [PasteboardRepresentation], onRead: @escaping @MainActor () -> Void) -> Int {
        let item = PasteboardItemSnapshot(representations: [PasteboardRepresentation(type: PasteboardTypes.string, data: Data(text.utf8))] + markers)
        items = [item]
        readHandler = onRead
        changeCount += 1
        writes.append(Write(kind: .lazyText, time: clock?.time ?? 0, text: text, hasMarkers: Self.hasMarkers([item])))
        return changeCount
    }

    func plainString() -> String? {
        let value = items.first?.representations.first { $0.type == PasteboardTypes.string }.map { String(decoding: $0.data, as: UTF8.self) }
        if let hook = afterPlainStringRead {
            afterPlainStringRead = nil
            hook()
        }
        return value
    }

    // MARK: Simulating the outside world

    /// Another app (or the user) puts something on the pasteboard.
    func externalCopy(_ text: String, extra: [PasteboardRepresentation] = []) {
        items = [PasteboardItemSnapshot(representations: [PasteboardRepresentation(type: PasteboardTypes.string, data: Data(text.utf8))] + extra)]
        changeCount += 1
    }

    func externalReplace(with newItems: [PasteboardItemSnapshot]) {
        items = newItems
        changeCount += 1
    }

    func externalClear() {
        items = []
        changeCount += 1
    }

    /// The pasting app asks for the text.
    func simulateAppRead() {
        let handler = readHandler
        readHandler = nil
        handler?()
    }

    /// The items with the clipboard-manager markers removed, to compare with what was there before.
    var itemsWithoutMarkers: [PasteboardItemSnapshot] {
        items.map { item in
            PasteboardItemSnapshot(representations: item.representations.filter { !PasteboardMarkers.types.contains($0.type) })
        }
    }

    private static func hasMarkers(_ items: [PasteboardItemSnapshot]) -> Bool {
        guard let first = items.first else { return true }   // an empty restore has nowhere to put markers
        let types = Set(first.representations.map(\.type))
        return PasteboardMarkers.types.allSatisfy(types.contains)
    }
}

@MainActor
final class FakeKeystrokes: KeystrokeSending {
    private(set) var sent: [Keystroke] = []
    private(set) var sentAt: [TimeInterval] = []
    var clock: FakeClock?
    var onSend: (@MainActor (Keystroke) -> Void)?

    func send(_ keystroke: Keystroke) async {
        sent.append(keystroke)
        sentAt.append(clock?.time ?? 0)
        onSend?(keystroke)
    }
}

@MainActor
final class FakeModifiers: ModifierKeyWatching {
    /// How many times the answer is "held" before the keys are let go.
    var heldChecks = 0
    private var checks = 0
    var anyModifierHeld: Bool {
        defer { checks += 1 }
        return checks < heldChecks
    }
}

@MainActor
final class FakeSecureInput: SecureInputChecking {
    var isSecureInputEnabled = false
}

@MainActor
final class TextEnvironment {
    let clock = FakeClock()
    let pasteboard: FakePasteboard
    let keys = FakeKeystrokes()
    let modifiers = FakeModifiers()
    let secure = FakeSecureInput()
    let service: SelectedTextService

    init(items: [PasteboardItemSnapshot] = [], timing: SelectedTextTiming = .standard) {
        pasteboard = FakePasteboard(items: items)
        pasteboard.clock = clock
        keys.clock = clock
        service = SelectedTextService(pasteboard: pasteboard, keys: keys, modifiers: modifiers, secureInput: secure, clock: clock, timing: timing)
    }

    /// Cmd+C copies `text` after `delay` seconds, like an app that answers a bit late.
    func appCopies(_ text: String, after delay: TimeInterval = 0) {
        keys.onSend = { [pasteboard, clock] keystroke in
            guard keystroke == .copy else { return }
            if delay == 0 { pasteboard.externalCopy(text) } else { clock.schedule(after: delay) { pasteboard.externalCopy(text) } }
        }
    }
}

func rep(_ type: String, _ text: String) -> PasteboardRepresentation {
    PasteboardRepresentation(type: type, data: Data(text.utf8))
}

func item(_ reps: PasteboardRepresentation...) -> PasteboardItemSnapshot {
    PasteboardItemSnapshot(representations: reps)
}

/// A clipboard with two items and several types each, none of them just a string.
func richClipboard() -> [PasteboardItemSnapshot] {
    [
        item(rep(PasteboardTypes.string, "old text"), rep("public.rtf", "{\\rtf1 old}"), rep("com.example.custom", "custom")),
        item(rep("public.file-url", "file:///tmp/a.txt"), rep("public.png", "PNGDATA")),
    ]
}

// MARK: Text-action doubles

@MainActor
final class FakeSelectedText: SelectedTextServing {
    var selection: String?
    var error: ActionError?
    private(set) var replacedWith: String?
    private(set) var pastePlainCalls = 0

    func transformSelection(_ transform: (String) throws -> String) async throws -> Bool {
        if let error { throw error }
        guard let selection else { throw ActionError.failed("No text selected") }
        let result = try transform(selection)
        guard result != selection else { return false }
        replacedWith = result
        return true
    }

    func pastePlainClipboard() async throws {
        if let error { throw error }
        pastePlainCalls += 1
    }
}

@MainActor
final class FakeInputSources: InputSourceSwitching {
    private(set) var selected: [String] = []
    var failure: String?

    func select(inputSourceID: String) throws {
        if let failure { throw ActionError.failed(failure) }
        selected.append(inputSourceID)
    }
}
