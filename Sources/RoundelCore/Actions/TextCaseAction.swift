import Foundation

/// Changes the case of the selected text in the frontmost app: upper, lower, title, sentence or toggle.
public struct TextCaseAction: Action {
    public let id = "text.case"
    public let title = "Change Case"
    public let defaultIcon: Icon = .symbol("textformat")
    public var acceptedInputs: Set<ActionInput> { [.text] }
    public var permissions: Set<Permission> { [.accessibility] }
    public var paramRules: ParamRules {
        ParamRules(specs: [.string("mode", required: true, allowed: TextCase.allCases.map(\.rawValue))])
    }

    private let text: any SelectedTextServing

    public init(text: any SelectedTextServing) {
        self.text = text
    }

    public func timeout(for params: Params) -> Duration { .seconds(10) }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let mode = context.params.string("mode").flatMap(TextCase.init(rawValue:)) else {
            throw ActionError.failed("mode must be one of: \(TextCase.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        _ = try await text.transformSelection { mode.apply($0) }
        return .done
    }
}
