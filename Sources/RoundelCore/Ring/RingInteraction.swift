import Foundation

/// What the host should do after feeding an event to `RingInteraction`.
public enum RingOutcome: Equatable, Sendable {
    case none
    /// Ring just opened; show the panel.
    case opened
    /// The visible level changed (entered a group or went back); redraw and re-feed the pointer position.
    case levelChanged
    /// Commit the action node with this id and close.
    case select(String)
    /// Close without committing.
    case dismiss
}

/// What a click landed on, as classified by the host from the pointer position.
public enum ClickTarget: Equatable, Sendable {
    case section(Int)
    /// The dead zone in the middle.
    case center
    /// Beyond the drawn ring, or in another app.
    case outside
}

/// Pure state machine for open / hover / dwell / navigate / commit. No AppKit and no timers: the host calls
/// `update(section:now:)` regularly with a monotonic clock and acts on the returned outcome.
public struct RingInteraction: Sendable {
    public private(set) var isOpen = false
    /// Locked when the ring opens.
    public private(set) var mode: OpenMode = .holdRelease
    /// Ids of the groups entered so far, outermost first.
    public private(set) var path: [String] = []
    public private(set) var currentNodes: [Node] = []
    public private(set) var highlighted: Int?

    public var depth: Int { path.count }

    private var root: [Node] = []
    private var dwellDuration: TimeInterval = 0.25
    private var centerDwellDuration: TimeInterval = 0.25
    private var dwell = Dwell.none
    private var suppression = Suppression.none

    private enum Dwell: Equatable, Sendable {
        case none
        case group(index: Int, since: TimeInterval)
        case center(since: TimeInterval)

        func withStart(_ now: TimeInterval) -> Dwell {
            switch self {
            case .none: .none
            case .group(let index, _): .group(index: index, since: now)
            case .center: .center(since: now)
            }
        }
    }

    /// Stops a dwell from re-triggering by itself right after the ring changed under a stationary cursor.
    private enum Suppression: Equatable, Sendable {
        case none
        /// A group was just entered; the next pointer sample says which child section is under the cursor.
        case awaitingFirstSample
        /// Ignore dwell on this section until the pointer is somewhere else.
        case section(Int)
        /// Went back and the pointer is parked in the center; ignore center dwell until it leaves.
        case center
    }

    public init() {}

    // MARK: Hotkey

    public mutating func hotkeyDown(config: RoundelConfig) -> RingOutcome {
        if !isOpen {
            isOpen = true
            mode = config.settings.openMode
            root = config.ring
            dwellDuration = config.settings.dwell
            centerDwellDuration = config.settings.centerDwell
            path = []
            currentNodes = root
            highlighted = nil
            dwell = .none
            suppression = .none
            return .opened
        }
        // Pressing the hotkey again while a click-required ring is open closes it, from any depth.
        if mode == .clickRequired { return close(.dismiss) }
        return .none
    }

    public mutating func hotkeyUp() -> RingOutcome {
        guard isOpen, mode == .holdRelease else { return .none }
        guard let index = highlighted, currentNodes.indices.contains(index) else { return close(.dismiss) }
        switch currentNodes[index] {
        case .action(let action): return close(.select(action.id))
        case .group: return close(.dismiss)   // releasing on a group cancels
        }
    }

    public mutating func escape() -> RingOutcome {
        guard isOpen else { return .none }
        return close(.dismiss)
    }

    // MARK: Pointer

    /// `section` is the section under the pointer in the current level, or `nil` in the center dead zone.
    /// Indices outside the current level are ignored.
    public mutating func update(section: Int?, now: TimeInterval) -> RingOutcome {
        guard isOpen else { return .none }
        if let section, !currentNodes.indices.contains(section) { return .none }

        highlighted = section
        guard mode == .holdRelease else { return .none }   // click mode never dwells

        resolveSuppression(for: section)

        let target = dwellTarget(for: section)
        switch (dwell, target) {
        case (.group(let a, _), .group(let b, _)) where a == b:
            break
        case (.center, .center):
            break
        default:
            dwell = target.withStart(now)
        }

        switch dwell {
        case .group(let index, let since) where now - since >= dwellDuration:
            return enterGroup(at: index)
        case .center(let since) where now - since >= centerDwellDuration:
            return goBack()
        default:
            return .none
        }
    }

    /// 0...1 progress of the running dwell, for drawing feedback. `nil` when nothing is dwelling.
    public func dwellProgress(at now: TimeInterval) -> Double? {
        switch dwell {
        case .none: nil
        case .group(_, let since): min(1, max(0, (now - since) / dwellDuration))
        case .center(let since): min(1, max(0, (now - since) / centerDwellDuration))
        }
    }

    // MARK: Click

    public mutating func click(_ target: ClickTarget) -> RingOutcome {
        guard isOpen, mode == .clickRequired else { return .none }
        switch target {
        case .outside:
            return close(.dismiss)
        case .center:
            return depth > 0 ? goBack() : close(.dismiss)
        case .section(let index):
            guard currentNodes.indices.contains(index) else { return .none }
            switch currentNodes[index] {
            case .action(let action): return close(.select(action.id))
            case .group: return enterGroup(at: index)
            }
        }
    }

    // MARK: Private

    private func dwellTarget(for section: Int?) -> Dwell {
        guard let section else {
            guard depth > 0, suppression != .center else { return .none }
            return .center(since: 0)
        }
        guard currentNodes[section].isGroup, suppression != .section(section) else { return .none }
        return .group(index: section, since: 0)
    }

    private mutating func resolveSuppression(for section: Int?) {
        switch suppression {
        case .none:
            break
        case .awaitingFirstSample:
            suppression = section.map(Suppression.section) ?? .center
        case .section(let suppressed):
            if section != suppressed { suppression = .none }
        case .center:
            if section != nil { suppression = .none }
        }
    }

    private mutating func enterGroup(at index: Int) -> RingOutcome {
        guard currentNodes.indices.contains(index), let children = currentNodes[index].children else { return .none }
        path.append(currentNodes[index].id)
        currentNodes = children
        highlighted = nil
        dwell = .none
        suppression = .awaitingFirstSample
        return .levelChanged
    }

    private mutating func goBack() -> RingOutcome {
        guard depth > 0 else { return .none }
        path.removeLast()
        currentNodes = nodes(at: path)
        highlighted = nil
        dwell = .none
        suppression = .center
        return .levelChanged
    }

    private func nodes(at path: [String]) -> [Node] {
        var level = root
        for id in path {
            guard let children = level.first(where: { $0.id == id })?.children else { return root }
            level = children
        }
        return level
    }

    private mutating func close(_ outcome: RingOutcome) -> RingOutcome {
        isOpen = false
        path = []
        currentNodes = []
        root = []
        highlighted = nil
        dwell = .none
        suppression = .none
        return outcome
    }
}
