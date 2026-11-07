import Foundation

public enum ConfigChange: Equatable, Sendable {
    /// New valid config; apply it.
    case updated
    /// File is valid and equals what is already loaded, but a previous error is now cleared.
    case recovered
    /// Nothing new (same bytes as last time, valid or invalid).
    case unchanged
    /// Invalid; the last good config stays active.
    case rejected(ConfigLoadFailure)
}

/// Holds the active config and the "keep last good" rule. Pure: the host feeds file contents in.
public struct ConfigState: Sendable {
    public private(set) var config: RoundelConfig
    public private(set) var lastFailure: ConfigLoadFailure?
    private var lastData: Data?
    private var lastBadData: Data?

    public init(initial: RoundelConfig) {
        self.config = initial
    }

    public mutating func apply(_ data: Data) -> ConfigChange {
        if let lastBadData, lastBadData == data { return .unchanged }
        if lastFailure == nil, let lastData, lastData == data { return .unchanged }

        switch ConfigLoader.parse(data) {
        case .failure(let failure):
            lastBadData = data
            lastFailure = failure
            return .rejected(failure)
        case .success(let parsed):
            let hadFailure = lastFailure != nil
            lastFailure = nil
            lastBadData = nil
            lastData = data
            if parsed == config { return hadFailure ? .recovered : .unchanged }
            config = parsed
            return .updated
        }
    }
}
