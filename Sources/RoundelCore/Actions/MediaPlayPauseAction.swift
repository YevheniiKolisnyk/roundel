import Foundation

/// Sends the Play / Pause media key to whatever app currently controls media. Needs the Accessibility permission.
public struct MediaPlayPauseAction: Action {
    public let id = "media.playPause"
    public let title = "Play / Pause"
    public let defaultIcon: Icon = .symbol("playpause.fill")
    public var paramRules: ParamRules { ParamRules(specs: []) }
    public var permissions: Set<Permission> { [.accessibility] }

    private let media: any MediaKeySending

    public init(media: any MediaKeySending) {
        self.media = media
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        await media.send(.playPause)
        return .done
    }
}
