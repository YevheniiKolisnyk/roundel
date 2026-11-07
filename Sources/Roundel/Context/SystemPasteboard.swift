import AppKit
import RoundelCore

/// The general pasteboard. Snapshots keep every item and every type; the text of a paste is offered lazily so the
/// moment the app asks for it can be observed.
@MainActor
final class SystemPasteboard: PasteboardAccessing {
    private let pasteboard: NSPasteboard
    /// The pasteboard does not necessarily keep its data providers alive.
    private var provider: LazyTextProvider?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot(limitBytes: Int) throws -> PasteboardSnapshot {
        var total = 0
        var items: [PasteboardItemSnapshot] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [PasteboardRepresentation] = []
            for type in item.types {
                // "dyn.…" types are aliases macOS generates for legacy types; they come back by themselves.
                if type.rawValue.hasPrefix("dyn.") { continue }
                guard let data = item.data(forType: type) else { throw PasteboardSnapshotError.incomplete }
                total += data.count
                if total > limitBytes { throw PasteboardSnapshotError.tooLarge }
                representations.append(PasteboardRepresentation(type: type.rawValue, data: data))
            }
            items.append(PasteboardItemSnapshot(representations: representations))
        }
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    func write(_ items: [PasteboardItemSnapshot]) -> Int {
        provider = nil
        pasteboard.clearContents()
        let objects = items.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in snapshot.representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            return item
        }
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
        return pasteboard.changeCount
    }

    @discardableResult
    func writeLazyText(_ text: String, markers: [PasteboardRepresentation], onRead: @escaping @MainActor () -> Void) -> Int {
        let lazy = LazyTextProvider(text: text, onRead: onRead)
        provider = lazy
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for marker in markers { item.setData(marker.data, forType: NSPasteboard.PasteboardType(marker.type)) }
        item.setDataProvider(lazy, forTypes: [.string])
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    func plainString() -> String? {
        pasteboard.string(forType: .string)
    }
}

/// Supplies the text when an app asks for it, and tells the service that the paste is being read.
private final class LazyTextProvider: NSObject, NSPasteboardItemDataProvider {
    private let text: String
    private let onRead: @MainActor () -> Void

    init(text: String, onRead: @escaping @MainActor () -> Void) {
        self.text = text
        self.onRead = onRead
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        DispatchQueue.main.async { [onRead] in
            MainActor.assumeIsolated { onRead() }
        }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}
