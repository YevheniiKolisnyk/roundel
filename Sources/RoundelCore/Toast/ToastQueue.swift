import Foundation

/// The stack of toasts as a pure state machine; time is passed in. It decides what is visible (the newest few), what is
/// counted as "+N more", and when each toast leaves. Showing anything is somebody else's job.
///
/// Each toast has its own clock that runs only while it is visible and the stack is not paused (the pointer is over
/// it), so a toast pushed out of view by newer ones waits with its time intact instead of vanishing unseen.
public struct ToastQueue: Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public let id: Int
        public var message: ToastMessage
        /// Seconds left, or `nil` for a toast that stays until replaced (progress).
        public var remaining: TimeInterval?
    }

    public static let maxEntries = 20

    public let maxVisible: Int
    /// Newest first.
    public private(set) var entries: [Entry] = []
    public private(set) var isPaused = false
    private var nextID = 1
    private var lastTime: TimeInterval?

    public init(maxVisible: Int = DesignMetrics.standard.toastMaxVisible) {
        self.maxVisible = max(1, maxVisible)
    }

    public var visible: [Entry] { Array(entries.prefix(maxVisible)) }
    public var hiddenCount: Int { max(0, entries.count - maxVisible) }

    /// How long a toast stays: longer for warnings and errors, longer still for long text, never more than 10 s.
    /// `nil` for progress.
    public static func duration(for message: ToastMessage) -> TimeInterval? {
        let base: TimeInterval
        switch message.kind {
        case .progress: return nil
        case .success: base = 3
        case .warning, .error: base = 6
        }
        let characters = message.title.count + (message.detail?.count ?? 0)
        return min(10, base + Double(max(0, characters - 60)) * 0.04)
    }

    /// Adds a toast and returns its id.
    /// - Progress replaces the progress toast that is already there (same entry, new text).
    /// - Anything else removes progress toasts (the work is over) and, if the same message is already shown, refreshes
    ///   that one instead of stacking a copy.
    @discardableResult
    public mutating func push(_ message: ToastMessage, now: TimeInterval) -> Int {
        advance(to: now)

        if message.kind == .progress {
            if let index = entries.firstIndex(where: { $0.message.kind == .progress }) {
                entries[index].message = message
                return entries[index].id
            }
        } else {
            entries.removeAll { $0.message.kind == .progress }
            if let index = entries.firstIndex(where: { $0.message == message }) {
                var entry = entries.remove(at: index)
                entry.remaining = Self.duration(for: message)
                entries.insert(entry, at: 0)
                return entry.id
            }
        }

        let entry = Entry(id: nextID, message: message, remaining: Self.duration(for: message))
        nextID += 1
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        return entry.id
    }

    /// Lets time pass: visible toasts use up their clocks (unless paused) and expired ones leave. Time going backwards is ignored.
    public mutating func advance(to now: TimeInterval) {
        guard let last = lastTime else {
            lastTime = now
            return
        }
        guard now > last else { return }
        defer { lastTime = now }
        guard !isPaused else { return }

        var time = last
        while time < now - 1e-12 {
            let clocks = visible.compactMap(\.remaining)
            guard let soonest = clocks.min() else { break }
            let step = min(now - time, soonest)
            for index in entries.indices.prefix(maxVisible) {
                if let remaining = entries[index].remaining { entries[index].remaining = remaining - step }
            }
            time += step
            entries.removeAll { ($0.remaining ?? 1) <= 1e-9 }   // only a clock that reached zero; progress has none
        }
    }

    /// The pointer is over the stack (`true`) or has left it. Time up to `now` counts before the change.
    public mutating func setPaused(_ paused: Bool, now: TimeInterval) {
        advance(to: now)
        isPaused = paused
    }

    public mutating func dismiss(id: Int) {
        entries.removeAll { $0.id == id }
    }

    /// Seconds until the next visible toast leaves, for scheduling a timer; `nil` when nothing will (empty, paused,
    /// or only progress).
    public var secondsUntilNextExpiry: TimeInterval? {
        guard !isPaused else { return nil }
        return visible.compactMap(\.remaining).min()
    }
}
