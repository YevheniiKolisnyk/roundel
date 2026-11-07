import Foundation

/// Pasteboard type identifiers used by the text actions.
public enum PasteboardTypes {
    public static let string = "public.utf8-plain-text"
}

/// Markers from nspasteboard.org. Clipboard managers that follow the convention skip content carrying them,
/// so Roundel's temporary writes do not show up in their history.
public enum PasteboardMarkers {
    public static let transient = "org.nspasteboard.TransientType"
    public static let concealed = "org.nspasteboard.ConcealedType"
    public static let types: Set<String> = [transient, concealed]

    /// The marker representations (empty data, as the convention expects).
    public static var representations: [PasteboardRepresentation] {
        [PasteboardRepresentation(type: transient, data: Data()), PasteboardRepresentation(type: concealed, data: Data())]
    }

    /// The items with the markers on the first one. An empty pasteboard has no item to carry them.
    public static func applied(to items: [PasteboardItemSnapshot]) -> [PasteboardItemSnapshot] {
        guard var first = items.first else { return items }
        let present = Set(first.representations.map(\.type))
        first.representations += representations.filter { !present.contains($0.type) }
        return [first] + items.dropFirst()
    }
}

public struct PasteboardRepresentation: Equatable, Sendable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// One pasteboard item with the data of every type it offers.
public struct PasteboardItemSnapshot: Equatable, Sendable {
    public var representations: [PasteboardRepresentation]

    public init(representations: [PasteboardRepresentation]) {
        self.representations = representations
    }
}

/// Everything on the pasteboard: all items and all types, not only strings.
public struct PasteboardSnapshot: Equatable, Sendable {
    public var items: [PasteboardItemSnapshot]

    public init(items: [PasteboardItemSnapshot]) {
        self.items = items
    }

    public var byteCount: Int {
        items.reduce(0) { $0 + $1.representations.reduce(0) { $0 + $1.data.count } }
    }
}

/// Why a snapshot could not be taken. Either way the action stops: a clipboard that cannot be restored is never touched.
public enum PasteboardSnapshotError: Error, Equatable, Sendable {
    case tooLarge
    /// Some type offered by an item could not be read.
    case incomplete
}

@MainActor
public protocol PasteboardAccessing {
    var changeCount: Int { get }
    /// Reads every item and type. Throws `tooLarge` once the data passes `limitBytes`, `incomplete` if a type cannot be read.
    func snapshot(limitBytes: Int) throws -> PasteboardSnapshot
    /// Replaces the contents with exactly these items. Returns the new change count.
    @discardableResult func write(_ items: [PasteboardItemSnapshot]) -> Int
    /// Replaces the contents with one item whose text is only produced when an app asks for it, and reports that moment
    /// through `onRead`. `markers` are written eagerly. Returns the new change count.
    @discardableResult func writeLazyText(_ text: String, markers: [PasteboardRepresentation], onRead: @escaping @MainActor () -> Void) -> Int
    func plainString() -> String?
}

public enum Keystroke: Sendable {
    case copy, paste
}

/// Posts Cmd+C / Cmd+V to the frontmost app.
@MainActor
public protocol KeystrokeSending {
    func send(_ keystroke: Keystroke) async
}

/// Whether any of Command, Option, Control or Shift is physically held.
@MainActor
public protocol ModifierKeyWatching {
    var anyModifierHeld: Bool { get }
}

@MainActor
public protocol SecureInputChecking {
    var isSecureInputEnabled: Bool { get }
}

/// Time as the service sees it, so tests can run the waits instantly.
@MainActor
public protocol AsyncClock {
    func now() -> TimeInterval
    func sleep(for seconds: TimeInterval) async
}

@MainActor
public struct SystemAsyncClock: AsyncClock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func sleep(for seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// Switches the active keyboard layout.
@MainActor
public protocol InputSourceSwitching {
    func select(inputSourceID: String) throws
}
