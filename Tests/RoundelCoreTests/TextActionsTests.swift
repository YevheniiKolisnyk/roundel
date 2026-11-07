import XCTest
@testable import RoundelCore

@MainActor
final class TextActionsTests: XCTestCase {
    private let text = FakeSelectedText()
    private let sources = FakeInputSources()

    private func context(_ params: [String: JSONValue] = [:]) -> ActionContext {
        ActionContext(nodeID: "n", title: "Node", params: Params(.object(params)))
    }

    private func failureMessage(_ block: () async throws -> ActionResult) async -> String? {
        do { _ = try await block(); return nil } catch let error as ActionError { return error.message } catch { return "\(error)" }
    }

    // MARK: text.case

    func testCaseActionAppliesEveryMode() async throws {
        let action = TextCaseAction(text: text)
        let expected: [(String, String)] = [("upper", "HELLO WORLD"), ("lower", "hello world"), ("title", "Hello World"),
                                            ("sentence", "Hello world"), ("toggle", "hELLO World")]
        for (mode, result) in expected {
            text.selection = "Hello wORLD"
            _ = try await action.run(context(["mode": .string(mode)]))
            XCTAssertEqual(text.replacedWith, result, mode)
        }
    }

    func testCaseActionNeedsAValidMode() {
        let rules = TextCaseAction(text: text).paramRules
        XCTAssertTrue(rules.validate(.object([:]), actionID: "text.case").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["mode": .string("shout")]), actionID: "text.case").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["mode": .string("title")]), actionID: "text.case").isEmpty)
    }

    func testCaseActionPassesServiceErrorsThrough() async {
        text.error = ActionError.failed("No text selected")
        let message = await failureMessage { try await TextCaseAction(text: text).run(context(["mode": .string("upper")])) }
        XCTAssertEqual(message, "No text selected")
    }

    func testTextActionsNeedAccessibilityAndDeclareTextInput() {
        let actions: [any Action] = [TextCaseAction(text: text), PastePlainAction(text: text), SwapLayoutAction(text: text, inputSources: sources)]
        for action in actions {
            XCTAssertEqual(action.permissions, [.accessibility], action.id)
            XCTAssertEqual(action.acceptedInputs, [.text], action.id)
        }
        XCTAssertEqual(actions.map(\.id), ["text.case", "text.pastePlain", "text.swapLayout"])
    }

    // MARK: text.pastePlain

    func testPastePlainCallsTheService() async throws {
        _ = try await PastePlainAction(text: text).run(context())
        XCTAssertEqual(text.pastePlainCalls, 1)
    }

    func testPastePlainTakesNoParams() {
        XCTAssertTrue(PastePlainAction(text: text).paramRules.specs.isEmpty)
    }

    // MARK: text.swapLayout

    func testSwapLayoutFixesUkrainianAndRussian() async throws {
        let action = SwapLayoutAction(text: text, inputSources: sources)
        text.selection = "Ghbdsn"
        _ = try await action.run(context(["language": .string("uk")]))
        XCTAssertEqual(text.replacedWith, "Привіт")

        text.selection = "Ghbdtn"
        _ = try await action.run(context(["language": .string("ru")]))
        XCTAssertEqual(text.replacedWith, "Привет")

        text.selection = "Руддщ"
        _ = try await action.run(context(["language": .string("ru")]))
        XCTAssertEqual(text.replacedWith, "Hello", "direction is detected from the text")
    }

    func testSwapLayoutWithNothingToConvertFails() async {
        text.selection = "123 !?"
        let message = await failureMessage { try await SwapLayoutAction(text: text, inputSources: sources).run(context(["language": .string("uk")])) }
        XCTAssertEqual(message, "No letters to convert")
        XCTAssertNil(text.replacedWith)
    }

    func testSwapLayoutRequiresAKnownLanguage() {
        let rules = SwapLayoutAction(text: text, inputSources: sources).paramRules
        XCTAssertTrue(rules.validate(.object([:]), actionID: "text.swapLayout").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["language": .string("de")]), actionID: "text.swapLayout").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["language": .string("uk"), "switchInputSource": .bool(true)]), actionID: "text.swapLayout").isEmpty)
        XCTAssertTrue(rules.validate(.object(["language": .string("uk"), "switchInputSource": .string("yes")]), actionID: "text.swapLayout").contains { $0.blocksRun })
    }

    func testSwitchInputSourceSelectsTheLayoutOfTheResult() async throws {
        let action = SwapLayoutAction(text: text, inputSources: sources)
        let params: [String: JSONValue] = ["language": .string("uk"), "switchInputSource": .bool(true)]

        text.selection = "ghbdsn"
        _ = try await action.run(context(params))
        XCTAssertEqual(sources.selected, ["com.apple.keylayout.Ukrainian-PC"])

        text.selection = "привіт"
        _ = try await action.run(context(params))
        XCTAssertEqual(sources.selected.last, "com.apple.keylayout.US")
    }

    func testTheInputSourceIsLeftAloneByDefaultAndWhenDisabled() async throws {
        let action = SwapLayoutAction(text: text, inputSources: sources)
        text.selection = "ghbdsn"
        _ = try await action.run(context(["language": .string("uk")]))
        _ = try await action.run(context(["language": .string("uk"), "switchInputSource": .bool(false)]))
        XCTAssertTrue(sources.selected.isEmpty)
    }

    func testAFailedSwitchStillKeepsTheFixedTextAndTellsTheUser() async throws {
        sources.failure = "input source “Ukrainian-PC” is not enabled"
        text.selection = "ghbdsn"
        let result = try await SwapLayoutAction(text: text, inputSources: sources)
            .run(context(["language": .string("uk"), "switchInputSource": .bool(true)]))
        XCTAssertEqual(text.replacedWith, "привіт")
        XCTAssertEqual(result, .message("Text fixed, but the layout was not switched: input source “Ukrainian-PC” is not enabled"))
    }

    func testNoSwitchHappensWhenTheServiceFailed() async {
        text.error = ActionError.failed("No text selected")
        _ = await failureMessage {
            try await SwapLayoutAction(text: text, inputSources: sources)
                .run(context(["language": .string("uk"), "switchInputSource": .bool(true)]))
        }
        XCTAssertTrue(sources.selected.isEmpty)
    }

    // MARK: Registry and default config

    func testTheRegistryKnowsTheTextActions() {
        let registry = ActionRegistry.standard(services: Fakes().services)
        for id in ["text.case", "text.pastePlain", "text.swapLayout"] { XCTAssertTrue(registry.ids.contains(id), id) }
    }

    func testBothFixLayoutExamplesSwitchTheInputSource() throws {
        func find(_ id: String, in nodes: [Node]) -> ActionNode? {
            for node in nodes {
                switch node {
                case .action(let action) where action.id == id: return action
                case .group(let group): if let found = find(id, in: group.children) { return found }
                default: break
                }
            }
            return nil
        }
        for (id, language) in [("text.fixUk", "uk"), ("text.fixRu", "ru")] {
            let node = try XCTUnwrap(find(id, in: DefaultConfig.config.ring), id)
            XCTAssertEqual(node.action, "text.swapLayout")
            let params = Params(node.params)
            XCTAssertEqual(params.string("language"), language)
            XCTAssertEqual(params.bool("switchInputSource"), true)
        }
    }

    func testTheDefaultConfigHasOneExampleOfEveryCaseMode() {
        func collect(_ nodes: [Node]) -> [ActionNode] {
            nodes.flatMap { node -> [ActionNode] in
                switch node {
                case .action(let action): [action]
                case .group(let group): collect(group.children)
                }
            }
        }
        let modes = collect(DefaultConfig.config.ring).filter { $0.action == "text.case" }.compactMap { Params($0.params).string("mode") }
        XCTAssertEqual(Set(modes), Set(TextCase.allCases.map(\.rawValue)))
    }
}
