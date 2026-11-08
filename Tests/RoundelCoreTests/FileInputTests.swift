import XCTest
@testable import RoundelCore

/// Which actions are usable with and without a file drag, and how the executor hands files to actions.
@MainActor
final class FileInputTests: XCTestCase {
    private let reporter = FakeReporter()
    private let permissions = FakePermissions()

    private struct InputAction: Action {
        var id: String
        var title = "Input"
        var defaultIcon: Icon = .symbol("star")
        var paramRules = ParamRules(specs: [])
        var acceptedInputs: Set<ActionInput>
        var record: @Sendable (ActionContext) -> Void = { _ in }
        func run(_ context: ActionContext) async throws -> ActionResult { record(context); return .done }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _contexts: [ActionContext] = []
        var contexts: [ActionContext] { lock.withLock { _contexts } }
        func add(_ context: ActionContext) { lock.withLock { _contexts.append(context) } }
    }

    private func actionNode(_ action: String, id: String = "n") -> ActionNode { ActionNode(id: id, title: id, action: action) }

    // MARK: Usability

    func testActionsThatNeedNoFilesAreUsableWithoutADragAndDimmedDuringOne() {
        let plain = InputAction(id: "plain", acceptedInputs: [.none])
        XCTAssertTrue(plain.isUsable(duringFileDrag: false))
        XCTAssertFalse(plain.isUsable(duringFileDrag: true))
    }

    func testActionsThatNeedFilesAreDimmedWithoutADragAndUsableDuringOne() {
        let files = InputAction(id: "files", acceptedInputs: [.files])
        XCTAssertFalse(files.isUsable(duringFileDrag: false))
        XCTAssertTrue(files.isUsable(duringFileDrag: true))
    }

    func testActionsThatTakeEitherAreUsableInBothSituations() {
        let both = InputAction(id: "both", acceptedInputs: [.none, .files])
        XCTAssertTrue(both.isUsable(duringFileDrag: false))
        XCTAssertTrue(both.isUsable(duringFileDrag: true))
    }

    func testSelectedTextActionsStayUsableWithoutADragAndAreDimmedDuringOne() {
        let text = InputAction(id: "text", acceptedInputs: [.text])
        XCTAssertTrue(text.isUsable(duringFileDrag: false), "they read the selection, not the ring's input")
        XCTAssertFalse(text.isUsable(duringFileDrag: true))
    }

    func testRegistryDimsByInputAndStillDimsUnknownActions() {
        let registry = ActionRegistry([InputAction(id: "plain", acceptedInputs: [.none]), InputAction(id: "files", acceptedInputs: [.files])])
        XCTAssertTrue(registry.isAvailable(actionNode("plain")))
        XCTAssertFalse(registry.isAvailable(actionNode("files")))
        XCTAssertFalse(registry.isAvailable(actionNode("plain"), fileDrag: true))
        XCTAssertTrue(registry.isAvailable(actionNode("files"), fileDrag: true))
        XCTAssertFalse(registry.isAvailable(actionNode("ghost")))
        XCTAssertFalse(registry.isAvailable(actionNode("ghost"), fileDrag: true))
    }

    func testAnEmptyGroupIsDimmed() {
        let items = RingItem.items(for: [.group(GroupNode(id: "g", title: "g", children: [])),
                                         .group(GroupNode(id: "h", title: "h", children: [.action(ActionNode(id: "a", title: "a", action: "x"))]))])
        XCTAssertEqual(items.map(\.isDimmed), [true, false])
    }

    // MARK: Executor

    private func executor(_ actions: [any Action]) -> ActionExecutor {
        ActionExecutor(registry: ActionRegistry(actions), permissions: permissions, reporter: reporter)
    }

    func testFilesReachTheActionInTheContext() async {
        let box = Box()
        let action = InputAction(id: "files", acceptedInputs: [.files], record: { box.add($0) })
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        await executor([action]).execute(actionNode("files"), files: urls)
        XCTAssertEqual(box.contexts.first?.files, urls)
        XCTAssertTrue(reporter.toasts.isEmpty)
    }

    func testAnActionWithoutFilesGetsAnEmptyList() async {
        let box = Box()
        await executor([InputAction(id: "plain", acceptedInputs: [.none], record: { box.add($0) })]).execute(actionNode("plain"))
        XCTAssertEqual(box.contexts.first?.files, [])
    }

    func testFilesAreNotHandedToAnActionThatDoesNotTakeThem() async {
        let box = Box()
        let action = InputAction(id: "plain", acceptedInputs: [.none], record: { box.add($0) })
        await executor([action]).execute(actionNode("plain"), files: [URL(fileURLWithPath: "/tmp/a.png")])
        XCTAssertTrue(box.contexts.isEmpty)
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].isError)
        XCTAssertTrue(reporter.toasts[0].message.contains("doesn’t take files"), reporter.toasts[0].message)
    }

    func testAnActionThatNeedsFilesRefusesToRunWithoutThem() async {
        let box = Box()
        let action = InputAction(id: "files", acceptedInputs: [.files], record: { box.add($0) })
        await executor([action]).execute(actionNode("files"))
        XCTAssertTrue(box.contexts.isEmpty)
        XCTAssertTrue(reporter.toasts[0].message.contains("needs files"), reporter.toasts[0].message)
    }

    func testProgressMessagesGoToTheReporterNotToTheToastList() async {
        struct Chatty: Action {
            var id = "chatty"; var title = "Chatty"; var defaultIcon: Icon = .symbol("x")
            var paramRules = ParamRules(specs: [])
            func run(_ context: ActionContext) async throws -> ActionResult {
                context.reportProgress("Working 1/2")
                context.reportProgress("Working 2/2")
                return .message("Done")
            }
        }
        await executor([Chatty()]).execute(actionNode("chatty"))
        try? await Task.sleep(for: .milliseconds(50))   // progress hops to the main actor
        XCTAssertEqual(reporter.progressMessages, ["Working 1/2", "Working 2/2"])
        XCTAssertEqual(reporter.toasts.map(\.message), ["Done"])
    }

    func testTheKindOfEachToastFollowsWhatHappened() async {
        struct Mixed: Action {
            var id = "mixed"; var title = "Mixed"; var defaultIcon: Icon = .symbol("x")
            var paramRules = ParamRules(specs: [.string("mode")])
            func run(_ context: ActionContext) async throws -> ActionResult {
                switch context.params.string("mode") {
                case "warn": return .warning("2 of 3 done · 1 failed")
                case "fail": throw ActionError.failed("nope")
                default: return .message("Done")
                }
            }
        }
        for (mode, kind) in [("ok", ToastKind.success), ("warn", .warning), ("fail", .error)] {
            let node = ActionNode(id: "n", title: "n", action: "mixed", params: .object(["mode": .string(mode)]))
            await executor([Mixed()]).execute(node)
        }
        XCTAssertEqual(reporter.kinds, [.success, .warning, .error])
    }

    func testAWarningResultIsShownAsAnErrorStyleToast() async {
        struct Partial: Action {
            var id = "partial"; var title = "Partial"; var defaultIcon: Icon = .symbol("x")
            var paramRules = ParamRules(specs: [])
            func run(_ context: ActionContext) async throws -> ActionResult { .warning("2 of 3 done · 1 failed") }
        }
        await executor([Partial()]).execute(actionNode("partial"))
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].isError)
        XCTAssertEqual(reporter.toasts[0].message, "2 of 3 done · 1 failed")
    }

    func testTheTimeoutCanDependOnTheNumberOfFiles() async {
        struct Slow: Action {
            var id = "slow"; var title = "Slow"; var defaultIcon: Icon = .symbol("x")
            var paramRules = ParamRules(specs: [])
            var acceptedInputs: Set<ActionInput> { [.files] }
            func timeout(for params: Params, fileCount: Int) -> Duration { .milliseconds(fileCount * 20) }
            func run(_ context: ActionContext) async throws -> ActionResult {
                try await Task.sleep(for: .milliseconds(150))
                return .done
            }
        }
        let many = (0..<10).map { URL(fileURLWithPath: "/tmp/\($0).png") }
        await executor([Slow()]).execute(actionNode("slow"), files: many)
        XCTAssertTrue(reporter.toasts.isEmpty, "10 files get 200 ms, enough for 150 ms of work")
        await executor([Slow()]).execute(actionNode("slow"), files: [many[0]])
        XCTAssertTrue(reporter.toasts.last?.message.contains("timed out") ?? false, "1 file gets 20 ms")
    }

    // MARK: Number params and the text icon

    func testNumberParamsAreValidatedAgainstTheirRange() {
        let rules = ParamRules(specs: [.number("quality", range: 0...1)])
        XCTAssertTrue(rules.validate(.object(["quality": .number(0.85)]), actionID: "x").isEmpty)
        XCTAssertTrue(rules.validate(.object(["quality": .number(0)]), actionID: "x").isEmpty)
        XCTAssertTrue(rules.validate(.object(["quality": .number(1)]), actionID: "x").isEmpty)
        XCTAssertTrue(rules.validate(.object(["quality": .number(1.5)]), actionID: "x").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["quality": .number(-0.1)]), actionID: "x").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["quality": .string("high")]), actionID: "x").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object([:]), actionID: "x").isEmpty)
        XCTAssertEqual(Params(.object(["quality": .number(0.5)])).double("quality"), 0.5)
        XCTAssertEqual(Params(.object(["quality": .number(1)])).double("quality"), 1)
        XCTAssertNil(Params(.object([:])).double("quality"))
    }

    func testTheTextIconDecodesAndRoundTrips() throws {
        let icon = try JSONDecoder().decode(Icon.self, from: Data(#"{"text": "PNG"}"#.utf8))
        XCTAssertEqual(icon, .text("PNG"))
        let data = try JSONEncoder().encode(icon)
        XCTAssertEqual(try JSONDecoder().decode(Icon.self, from: data), icon)
        XCTAssertThrowsError(try JSONDecoder().decode(Icon.self, from: Data(#"{"text": "  "}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Icon.self, from: Data(#"{"text": "A", "symbol": "star"}"#.utf8)))
    }
}

/// Choosing a node by id when the ring commits: an id that is not an action must be said out loud, not only logged.
@MainActor
final class ExecuteByIDTests: XCTestCase {
    private let reporter = FakeReporter()

    private func executor() -> ActionExecutor {
        ActionExecutor(registry: ActionRegistry([StubAction()]), permissions: FakePermissions(), reporter: reporter)
    }

    private let config = RoundelConfig(ring: [
        .action(ActionNode(id: "run", title: "Run me", action: "stub.action")),
        .group(GroupNode(id: "folder", title: "A folder", children: [.action(ActionNode(id: "inner", title: "Inner", action: "stub.action"))])),
    ])

    func testAnActionIdRunsTheAction() async {
        await executor().execute(nodeWithID: "inner", in: config)
        XCTAssertTrue(reporter.toasts.isEmpty)
        XCTAssertTrue(reporter.infos.contains { $0.contains("inner") }, "\(reporter.infos)")
    }

    func testAnIdThatIsNotInTheConfigIsToastedAsAnError() async {
        await executor().execute(nodeWithID: "ghost", in: config)
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].isError)
        XCTAssertTrue(reporter.toasts[0].message.contains("ghost"), reporter.toasts[0].message)
        XCTAssertFalse(reporter.warnings.isEmpty, "and it is logged too")
    }

    func testAGroupIdIsToastedAsAnError() async {
        await executor().execute(nodeWithID: "folder", in: config)
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].isError)
        XCTAssertTrue(reporter.toasts[0].message.contains("A folder"), reporter.toasts[0].message)
    }
}
