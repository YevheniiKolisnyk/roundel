import Foundation

/// Sends the Next Track media key to whatever app currently controls media. Needs the Accessibility permission.
public struct MediaNextAction: Action {
    public let id = "media.next"
    public let title = "Next Track"
    public let defaultIcon: Icon = .symbol("forward.fill")
    public var paramRules: ParamRules { ParamRules(specs: []) }
    public var permissions: Set<Permission> { [.accessibility] }

    private let media: any MediaKeySending

    public init(media: any MediaKeySending) {
        self.media = media
    }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        await media.send(.next)
        return .done
    }
}
