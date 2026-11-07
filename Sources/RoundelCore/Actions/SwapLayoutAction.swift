import Foundation

/// Fixes text typed in the wrong keyboard layout (English <-> Ukrainian or Russian), in the direction the text needs.
public struct SwapLayoutAction: Action {
    public let id = "text.swapLayout"
    public let title = "Fix Layout"
    public let defaultIcon: Icon = .symbol("keyboard")
    public var acceptedInputs: Set<ActionInput> { [.text] }
    public var permissions: Set<Permission> { [.accessibility] }
    public var paramRules: ParamRules {
        ParamRules(specs: [
            .string("language", required: true, allowed: LayoutTables.all.map(\.language)),
            .bool("switchInputSource"),
        ])
    }

    private let text: any SelectedTextServing
    private let inputSources: any InputSourceSwitching

    public init(text: any SelectedTextServing, inputSources: any InputSourceSwitching) {
        self.text = text
        self.inputSources = inputSources
    }

    public func timeout(for params: Params) -> Duration { .seconds(10) }

    @MainActor
    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let table = context.params.string("language").flatMap(LayoutTables.table(forLanguage:)) else {
            throw ActionError.failed("language must be one of: \(LayoutTables.all.map(\.language).joined(separator: ", "))")
        }

        var direction: SwapDirection?
        _ = try await text.transformSelection { selection in
            guard let swapped = LayoutSwapper.swap(selection, using: table) else { throw ActionError.failed("No letters to convert") }
            direction = swapped.direction
            return swapped.text
        }

        guard context.params.bool("switchInputSource") == true, let direction else { return .done }
        do {
            try inputSources.select(inputSourceID: table.inputSourceID(for: direction))
        } catch let error as ActionError {
            return .message("Text fixed, but the layout was not switched: \(error.message)")
        }
        return .done
    }
}
