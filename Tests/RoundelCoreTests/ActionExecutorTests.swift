import XCTest
@testable import RoundelCore

@MainActor
final class ActionExecutorTests: XCTestCase {
    private let reporter = FakeReporter()
    private let permissions = FakePermissions()

    private func executor(_ actions: [any Action]) -> ActionExecutor {
        ActionExecutor(registry: ActionRegistry(actions), permissions: permissions, reporter: reporter)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }

    // MARK: Unknown / invalid

    func testUnknownActionWarnsAndToastsWithoutRunning() async {
        let ran = Flag()
        let executor = executor([StubAction(behavior: { ran.set(); return .done })])
        await executor.execute(node("n", action: "ghost"))
        XCTAssertFalse(ran.isSet)
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].isError)
        XCTAssertTrue(reporter.toasts[0].message.contains("ghost"), reporter.toasts[0].message)
        XCTAssertFalse(reporter.warnings.isEmpty)
    }

    func testBlockingParamProblemStopsTheRunAndNamesTheField() async {
        let ran = Flag()
        let action = StubAction(paramRules: ParamRules(specs: [.string("url", required: true)]), behavior: { ran.set(); return .done })
        await executor([action]).execute(node("n"))
        XCTAssertFalse(ran.isSet)
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].message.contains("\"url\" is required"), reporter.toasts[0].message)
        XCTAssertTrue(reporter.toasts[0].isError)
    }

    func testNonBlockingProblemStillRunsAndOnlyLogs() async {
        let ran = Flag()
        let action = StubAction(paramRules: ParamRules(specs: []), behavior: { ran.set(); return .done })
        await executor([action]).execute(node("n", params: .object(["extra": .bool(true)])))
        XCTAssertTrue(ran.isSet)
        XCTAssertTrue(reporter.toasts.isEmpty)
        XCTAssertEqual(reporter.warnings.count, 1)
    }

    func testExtraValidationBlocks() async {
        struct Picky: Action {
            var id = "picky"; var title = "Picky"; var defaultIcon: Icon = .symbol("x")
            var paramRules = ParamRules(specs: [])
            func extraValidation(_ params: Params) -> [ParamIssue] { [ParamIssue(message: "nope", blocksRun: true)] }
            func run(_ context: ActionContext) async throws -> ActionResult { .done }
        }
        await executor([Picky()]).execute(node("n", action: "picky"))
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].message.contains("nope"))
    }

    // MARK: Results

    func testSuccessIsSilentButMessageResultsToast() async {
        await executor([StubAction(behavior: { .done })]).execute(node("n"))
        XCTAssertTrue(reporter.toasts.isEmpty)

        let messaging = StubAction(behavior: { .message("Caffeinate on") })
        await executor([messaging]).execute(node("n"))
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertEqual(reporter.toasts[0].message, "Caffeinate on")
        XCTAssertFalse(reporter.toasts[0].isError)
    }

    func testActionErrorBecomesAnErrorToastWithTheActionTitle() async {
        let action = StubAction(title: "Open App", behavior: { throw ActionError.failed("Safari not found") })
        await executor([action]).execute(node("n"))
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].isError)
        XCTAssertTrue(reporter.toasts[0].message.contains("Open App"), reporter.toasts[0].message)
        XCTAssertTrue(reporter.toasts[0].message.contains("Safari not found"), reporter.toasts[0].message)
    }

    func testUnexpectedErrorsDoNotCrashAndAreReported() async {
        struct Weird: LocalizedError { var errorDescription: String? { "weird failure" } }
        await executor([StubAction(behavior: { throw Weird() })]).execute(node("n"))
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].message.contains("weird failure"))
    }

    func testCancellationInsideTheActionIsSilent() async {
        await executor([StubAction(behavior: { throw CancellationError() })]).execute(node("n"))
        XCTAssertTrue(reporter.toasts.isEmpty)
    }

    // MARK: Timeout

    func testTimeoutCancelsTheActionAndReports() async {
        let cancelled = Flag()
        let action = StubAction(title: "Slow", timeoutValue: .milliseconds(80), behavior: {
            do { try await Task.sleep(for: .seconds(30)) } catch { cancelled.set(); throw error }
            return .done
        })
        let started = ContinuousClock.now
        await executor([action]).execute(node("n"))
        let elapsed = ContinuousClock.now - started

        XCTAssertLessThan(elapsed, .seconds(5), "must not wait for the slow action")
        XCTAssertTrue(cancelled.isSet, "the action saw cancellation (so a real process gets killed)")
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].message.contains("timed out"), reporter.toasts[0].message)
        XCTAssertTrue(reporter.toasts[0].isError)
    }

    func testFastActionIsNotAffectedByTimeout() async {
        await executor([StubAction(timeoutValue: .seconds(5), behavior: { .message("fine") })]).execute(node("n"))
        XCTAssertEqual(reporter.toasts.map(\.message), ["fine"])
    }

    // MARK: Permissions

    func testDeniedPermissionRequestsItAndDoesNotRun() async {
        permissions.statuses[.accessibility] = .denied
        let ran = Flag()
        let action = StubAction(title: "Play", permissions: [.accessibility], behavior: { ran.set(); return .done })
        await executor([action]).execute(node("n"))

        XCTAssertFalse(ran.isSet)
        XCTAssertEqual(permissions.requested, [.accessibility])
        XCTAssertEqual(reporter.toasts.count, 1)
        XCTAssertTrue(reporter.toasts[0].message.contains("Accessibility"), reporter.toasts[0].message)
        XCTAssertTrue(reporter.toasts[0].isError)
    }

    func testNotDeterminedPermissionStillTriesSoTheSystemCanAsk() async {
        permissions.statuses[.automationSystemEvents] = .notDetermined
        let ran = Flag()
        let action = StubAction(permissions: [.automationSystemEvents], behavior: { ran.set(); return .done })
        await executor([action]).execute(node("n"))
        XCTAssertTrue(ran.isSet)
        XCTAssertTrue(permissions.requested.isEmpty)
    }

    func testGrantedPermissionRuns() async {
        permissions.statuses[.accessibility] = .granted
        let ran = Flag()
        await executor([StubAction(permissions: [.accessibility], behavior: { ran.set(); return .done })]).execute(node("n"))
        XCTAssertTrue(ran.isSet)
    }

    // MARK: Logging

    func testRunIsLoggedWithActionAndNode() async {
        await executor([StubAction()]).execute(node("n1"))
        XCTAssertTrue(reporter.infos.contains { $0.contains("stub.action") && $0.contains("n1") }, "\(reporter.infos)")
    }
}
