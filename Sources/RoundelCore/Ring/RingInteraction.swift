import Foundation

/// What the host should do after feeding an event to `RingInteraction`.
public enum RingOutcome: Equatable, Sendable {
    case none
    /// The ring just opened; show the panel.
    case opened
    /// Arcs opened or closed; rebuild the layout and the view.
    case layoutChanged
    /// Run the action node with this id and close.
    case select(String)
    /// Close without running anything.
    case dismiss
}

/// An item in the layout: `level` 0 is the root ring, level N is the arc opened by the Nth group of the chain.
public struct RingItemRef: Hashable, Sendable {
    public let level: Int
    public let index: Int

    public init(level: Int, index: Int) {
        self.level = level
        self.index = index
    }
}

/// Pure state machine for the expanding-arc ring. The host feeds it what is under the pointer (`RingHit`) and the time;
/// it decides which groups are open, what is highlighted and what a release or a click means.
///
/// Rules (the same hover logic in both modes):
/// - Hovering a group opens its arc after `expandDelay`. The arc belongs to a *chain* of open groups, one per level.
/// - While the pointer is on any open group's own section, or anywhere in the deepest arc, the chain does not change
///   (the "sticky parent").
/// - Hovering a different group at some level replaces the chain from that level on, after `expandDelay`.
/// - Hovering a leaf next to an open group, or being in a gap, the center or outside, closes arcs, but only after the
///   pointer has stayed away continuously for `closeHysteresis`, so a brief slip does not collapse the submenu.
/// - Click mode only: clicking a group pins its arc (pinned arcs ignore the "moved away" closing); clicking a pinned
///   group again closes it.
public struct RingInteraction: Sendable {
    public private(set) var isOpen = false
    /// Locked when the ring opens.
    public private(set) var mode: OpenMode = .holdRelease
    /// Ids of the open groups, outermost first. `path.count` arcs are open besides the root ring.
    public private(set) var path: [String] = []
    /// The first `pinnedDepth` groups of the chain are pinned (click mode).
    public private(set) var pinnedDepth = 0
    public private(set) var hovered: RingItemRef?

    public var levelCount: Int { path.count + 1 }

    private let closeHysteresis: TimeInterval
    private var expandDelay: TimeInterval = 0.12
    private var levels: [[Node]] = []
    private var pending = Pending.none
    /// A group the user just closed by clicking; it must not reopen while the pointer is still on it.
    private var suppressed: RingItemRef?

    private enum Pending: Equatable, Sendable {
        case none
        case expand(level: Int, id: String, since: TimeInterval)
        case collapse(toDepth: Int, since: TimeInterval)
    }

    /// Tolerance for comparing times, so 0.12 s after 0.1 s counts as 0.12 s despite floating point.
    private static let epsilon = 1e-9

    public init(metrics: RingMetrics = .standard) {
        closeHysteresis = metrics.closeHysteresis
    }

    // MARK: Reading the state

    public func nodes(atLevel level: Int) -> [Node] {
        levels.indices.contains(level) ? levels[level] : []
    }

    /// The open chain (one item per open group) plus the hovered item.
    public var highlightedItems: [RingItemRef] {
        var result: [RingItemRef] = []
        for (level, id) in path.enumerated() {
            if let index = nodes(atLevel: level).firstIndex(where: { $0.id == id }) {
                result.append(RingItemRef(level: level, index: index))
            }
        }
        if let hovered, !result.contains(hovered) { result.append(hovered) }
        return result
    }

    public func isHighlighted(level: Int, index: Int) -> Bool {
        highlightedItems.contains(RingItemRef(level: level, index: index))
    }

    // MARK: Hotkey

    public mutating func hotkeyDown(config: RoundelConfig) -> RingOutcome {
        if !isOpen {
            isOpen = true
            mode = config.settings.openMode
            expandDelay = config.settings.expandDelay
            levels = [config.ring]
            path = []
            pinnedDepth = 0
            hovered = nil
            pending = .none
            suppressed = nil
            return .opened
        }
        // Pressing the hotkey again while a click-required ring is open closes everything, at any depth.
        if mode == .clickRequired { return close(.dismiss) }
        return .none
    }

    public mutating func hotkeyUp() -> RingOutcome {
        guard isOpen, mode == .holdRelease else { return .none }
        guard let hovered, let node = node(at: hovered) else { return close(.dismiss) }
        switch node {
        case .action(let action): return close(.select(action.id))
        case .group: return close(.dismiss)   // releasing on a group cancels
        }
    }

    public mutating func escape() -> RingOutcome {
        guard isOpen else { return .none }
        return close(.dismiss)
    }

    // MARK: Pointer

    /// Call regularly (e.g. every frame) with what is under the pointer.
    public mutating func update(hit: RingHit, now: TimeInterval) -> RingOutcome {
        guard isOpen else { return .none }

        var ref: RingItemRef?
        if case .item(let level, let index) = hit, levels.indices.contains(level), levels[level].indices.contains(index) {
            ref = RingItemRef(level: level, index: index)
        }
        hovered = ref
        if let suppressed, suppressed != ref { self.suppressed = nil }

        // Center, gap, outside, or a hit that points at nothing: away from the chain.
        guard let ref, let node = node(at: ref) else { return scheduleCollapse(toDepth: 0, now: now) }

        if ref.level < path.count {
            if node.id == path[ref.level] {
                pending = .none   // on an open group's own section: everything stays
                return .none
            }
            // A sibling of an open group.
            return node.isGroup ? scheduleExpand(ref, node, now: now) : scheduleCollapse(toDepth: ref.level, now: now)
        }

        // In the deepest arc: a group opens its arc, a leaf just holds the chain.
        if node.isGroup { return scheduleExpand(ref, node, now: now) }
        pending = .none
        return .none
    }

    // MARK: Click

    /// `hit` is what the click landed on, classified by the host (clicks in other apps are `.outside`).
    public mutating func click(_ hit: RingHit) -> RingOutcome {
        guard isOpen, mode == .clickRequired else { return .none }
        switch hit {
        case .center, .outside:
            return close(.dismiss)
        case .gap:
            return .none
        case .item(let level, let index):
            let ref = RingItemRef(level: level, index: index)
            guard let node = node(at: ref) else { return .none }
            switch node {
            case .action(let action):
                return close(.select(action.id))
            case .group:
                if level < path.count, path[level] == node.id {
                    if pinnedDepth > level {
                        // Pinned: a second click closes its arc, and hovering must not instantly reopen it.
                        suppressed = ref
                        return truncate(toDepth: level)
                    }
                    pinnedDepth = level + 1   // opened by hover: pin it
                    return .none
                }
                let outcome = open(group: node, atLevel: level)
                pinnedDepth = level + 1
                return outcome
            }
        }
    }

    // MARK: Private

    private func node(at ref: RingItemRef) -> Node? {
        guard levels.indices.contains(ref.level), levels[ref.level].indices.contains(ref.index) else { return nil }
        return levels[ref.level][ref.index]
    }

    private mutating func scheduleExpand(_ ref: RingItemRef, _ node: Node, now: TimeInterval) -> RingOutcome {
        if suppressed == ref {
            pending = .none
            return .none
        }
        if case .expand(let level, let id, let since) = pending, level == ref.level, id == node.id {
            return now - since >= expandDelay - Self.epsilon ? open(group: node, atLevel: ref.level) : .none
        }
        pending = .expand(level: ref.level, id: node.id, since: now)
        return expandDelay <= Self.epsilon ? open(group: node, atLevel: ref.level) : .none
    }

    /// Closes arcs deeper than `depth` (but never below the pinned ones) once the pointer has been away long enough.
    private mutating func scheduleCollapse(toDepth depth: Int, now: TimeInterval) -> RingOutcome {
        let target = max(depth, pinnedDepth)
        guard path.count > target else {
            pending = .none
            return .none
        }
        if case .collapse(let to, let since) = pending, to == target {
            return now - since >= closeHysteresis - Self.epsilon ? truncate(toDepth: target) : .none
        }
        pending = .collapse(toDepth: target, since: now)
        return .none
    }

    /// Makes `node` the open group at `level`, replacing whatever was open from that level on.
    private mutating func open(group node: Node, atLevel level: Int) -> RingOutcome {
        path = Array(path.prefix(level)) + [node.id]
        levels = Array(levels.prefix(level + 1)) + [node.children ?? []]
        pinnedDepth = min(pinnedDepth, level)
        pending = .none
        return .layoutChanged
    }

    private mutating func truncate(toDepth depth: Int) -> RingOutcome {
        path = Array(path.prefix(depth))
        levels = Array(levels.prefix(depth + 1))
        pinnedDepth = min(pinnedDepth, depth)
        pending = .none
        return .layoutChanged
    }

    private mutating func close(_ outcome: RingOutcome) -> RingOutcome {
        isOpen = false
        path = []
        pinnedDepth = 0
        levels = []
        hovered = nil
        pending = .none
        suppressed = nil
        return outcome
    }
}
