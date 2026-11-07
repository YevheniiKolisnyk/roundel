import Foundation

/// Sends the Previous Track media key to whatever app currently controls media. Needs the Accessibility permission.
public struct MediaPreviousAction: Action {
    public let id = "media.previous"
    public let title = "Previous Track"
    public let defaultIcon: Icon = .symbol("backward.fill")
    public var paramRules: ParamRules { ParamRules(specs: []) }
    public var permissions: Set<Permission> { [.accessibility] }

    private let media: any MediaKeySending

    public init(media: any MediaKeySending) {
        self.media = media
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        await media.send(.previous)
        return .done
    }
}
