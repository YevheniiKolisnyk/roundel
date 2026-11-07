import AppKit

/// Tells whether the user is dragging files right now. There is no API for "a drag is in progress", so this combines:
/// the left button is down, the drag pasteboard offers file URLs, and the drag pasteboard changed since the last
/// ring session (it keeps its contents after a drag ends, so an unchanged pasteboard means stale files).
/// Only the types are checked here; the URLs are read from the drop itself.
@MainActor
final class FileDragProbe {
    private let pasteboard = NSPasteboard(name: .drag)
    private var consumedChangeCount: Int

    init() {
        consumedChangeCount = pasteboard.changeCount
    }

    func fileDragInProgress() -> Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0, pasteboard.changeCount != consumedChangeCount else { return false }
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// Call when a ring session ends: whatever the drag pasteboard holds now is old.
    func markConsumed() {
        consumedChangeCount = pasteboard.changeCount
    }
}
