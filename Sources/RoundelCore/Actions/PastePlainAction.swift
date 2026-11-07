import Foundation

/// Pastes what is on the clipboard as plain text, without capturing anything. The clipboard keeps its formatting.
public struct PastePlainAction: Action {
    public let id = "text.pastePlain"
    public let title = "Paste as Plain Text"
    public let defaultIcon: Icon = .symbol("doc.plaintext")
    public var acceptedInputs: Set<ActionInput> { [.text] }
    public var permissions: Set<Permission> { [.accessibility] }
    public var paramRules: ParamRules { ParamRules(specs: []) }

    private let text: any SelectedTextServing

    public init(text: any SelectedTextServing) {
        self.text = text
    }

    public func timeout(for params: Params) -> Duration { .seconds(10) }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        try await text.pastePlainClipboard()
        return .done
    }
}
