/// What the host should do after feeding an event to `RingInteraction`.
public enum RingOutcome: Equatable, Sendable {
    case none
    /// Ring just opened; show the panel.
    case opened
    /// Commit this section and close.
    case select(Int)
    /// Close without committing.
    case dismiss
}

/// Pure state machine for open / hover / commit. No AppKit, no timers: the host feeds events in and acts on the outcome.
public struct RingInteraction: Sendable {
    public private(set) var isOpen = false
    public private(set) var highlighted: Int?
    /// Locked when the ring opens, so changing the setting mid-session cannot change behavior under the user's hand.
    public private(set) var mode: OpenMode = .holdRelease

    public init() {}

    public mutating func hotkeyDown(mode: OpenMode) -> RingOutcome {
        if !isOpen {
            self.mode = mode
            isOpen = true
            highlighted = nil
            return .opened
        }
        // Pressing the hotkey again while a click-required ring is open toggles it closed.
        if self.mode == .clickRequired {
            return close(.dismiss)
        }
        return .none
    }

    public mutating func hotkeyUp() -> RingOutcome {
        guard isOpen, mode == .holdRelease else { return .none }
        if let highlighted { return close(.select(highlighted)) }
        return close(.dismiss)
    }

    public mutating func pointerMoved(section: Int?) {
        guard isOpen else { return }
        highlighted = section
    }

    /// `section` is the section under the click, or `nil` for the dead zone / outside the ring.
    public mutating func click(section: Int?) -> RingOutcome {
        guard isOpen, mode == .clickRequired else { return .none }
        if let section { return close(.select(section)) }
        return close(.dismiss)
    }

    public mutating func escape() -> RingOutcome {
        guard isOpen else { return .none }
        return close(.dismiss)
    }

    private mutating func close(_ outcome: RingOutcome) -> RingOutcome {
        isOpen = false
        highlighted = nil
        return outcome
    }
}
