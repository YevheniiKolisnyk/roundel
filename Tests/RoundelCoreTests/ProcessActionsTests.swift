import XCTest
@testable import RoundelCore

// Shell, Shortcuts, Do Not Disturb, lock screen fallback, dark mode: everything that goes through ProcessRunning.
@MainActor
final class ProcessActionsTests: XCTestCase {
    private let fakes = Fakes()

    private func context(_ action: any Action, _ params: [String: JSONValue]) -> ActionContext {
        ActionContext(nodeID: "n", title: "Node", params: Params(.object(params)))
    }

    private func failureMessage(_ block: () async throws -> ActionResult) async -> String? {
        do { _ = try await block(); return nil } catch let error as ActionError { return error.message } catch { return "\(error)" }
    }

    // MARK: Result mapping

    func testExitZeroIsSuccess() throws {
        XCTAssertEqual(try ProcessResultMapper.map(ProcessResult(exitStatus: 0, stdout: "hi\n"), label: "script"), .done)
    }

    func testNonZeroExitShowsStderr() {
        let result = ProcessResult(exitStatus: 2, stderr: "zsh: command not found: foo\n")
        XCTAssertThrowsError(try ProcessResultMapper.map(result, label: "Shell")) { error in
            XCTAssertEqual((error as? ActionError)?.message, "zsh: command not found: foo")
        }
    }

    func testNonZeroExitWithoutStderrMentionsStatus() {
        XCTAssertThrowsError(try ProcessResultMapper.map(ProcessResult(exitStatus: 3), label: "Shell")) { error in
            XCTAssertEqual((error as? ActionError)?.message, "Shell exited with status 3")
        }
    }

    func testLongStderrKeepsTheTailAndIsTruncated() {
        let lines = (1...40).map { "line \($0) " + String(repeating: "x", count: 30) }.joined(separator: "\n")
        XCTAssertThrowsError(try ProcessResultMapper.map(ProcessResult(exitStatus: 1, stderr: lines), label: "Shell")) { error in
            let message = (error as? ActionError)?.message ?? ""
            XCTAssertLessThanOrEqual(message.count, ProcessResultMapper.maxMessageLength + 1)
            XCTAssertTrue(message.contains("line 40"), "the end of stderr is the useful part")
            XCTAssertFalse(message.contains("line 1 "))
            XCTAssertTrue(message.hasPrefix("…"))
        }
    }

    func testKilledBySignal() {
        let result = ProcessResult(exitStatus: 9, terminatedBySignal: true)
        XCTAssertThrowsError(try ProcessResultMapper.map(result, label: "Shell")) { error in
            XCTAssertEqual((error as? ActionError)?.message, "Shell was terminated by signal 9")
        }
    }

    func testWhitespaceOnlyStderrFallsBackToStatus() {
        XCTAssertThrowsError(try ProcessResultMapper.map(ProcessResult(exitStatus: 1, stderr: " \n "), label: "X")) { error in
            XCTAssertEqual((error as? ActionError)?.message, "X exited with status 1")
        }
    }

    // MARK: shell.run

    func testShellBuildsZshDashC() async throws {
        let action = ShellRunAction(process: fakes.process)
        _ = try await action.run(context(action, ["script": .string("echo hi")]))
        let request = try XCTUnwrap(fakes.process.requests.first)
        XCTAssertEqual(request.executable, "/bin/zsh")
        XCTAssertEqual(request.arguments, ["-c", "echo hi", "zsh"])
        XCTAssertNil(request.workingDirectory)
    }

    func testShellPassesArgsAsPositionalParameters() async throws {
        let action = ShellRunAction(process: fakes.process)
        _ = try await action.run(context(action, ["script": .string("say \"$1\""), "args": .array([.string("a b"), .string("c")])]))
        XCTAssertEqual(fakes.process.requests.first?.arguments, ["-c", "say \"$1\"", "zsh", "a b", "c"])
    }

    func testShellLoginOption() async throws {
        let action = ShellRunAction(process: fakes.process)
        _ = try await action.run(context(action, ["script": .string("true"), "login": .bool(true)]))
        XCTAssertEqual(fakes.process.requests.first?.arguments.first, "-lc")
        _ = try await action.run(context(action, ["script": .string("true"), "login": .bool(false)]))
        XCTAssertEqual(fakes.process.requests.last?.arguments.first, "-c")
    }

    func testShellExpandsTildeInCwd() async throws {
        let action = ShellRunAction(process: fakes.process)
        _ = try await action.run(context(action, ["script": .string("pwd"), "cwd": .string("~/Projects")]))
        XCTAssertEqual(fakes.process.requests.first?.workingDirectory, NSHomeDirectory() + "/Projects")
    }

    func testShellNonZeroExitSurfacesStderr() async {
        fakes.process.result = ProcessResult(exitStatus: 127, stderr: "zsh:1: command not found: nope\n")
        let action = ShellRunAction(process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, ["script": .string("nope")])) }
        XCTAssertEqual(message, "zsh:1: command not found: nope")
    }

    func testShellLaunchFailureIsReadable() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "no such file" } }
        fakes.process.error = Boom()
        let action = ShellRunAction(process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, ["script": .string("x")])) }
        XCTAssertEqual(message, "could not start /bin/zsh: no such file")
    }

    func testShellTimeoutParamDefaultsAndLimits() {
        let action = ShellRunAction(process: fakes.process)
        XCTAssertEqual(action.timeout(for: Params(.object([:]))), .seconds(30))
        XCTAssertEqual(action.timeout(for: Params(.object(["timeoutSec": .number(5)]))), .seconds(5))
        let rules = action.paramRules
        XCTAssertFalse(rules.validate(.object(["script": .string("x"), "timeoutSec": .number(0)]), actionID: "shell.run").isEmpty)
        XCTAssertFalse(rules.validate(.object(["script": .string("x"), "timeoutSec": .number(601)]), actionID: "shell.run").isEmpty)
        XCTAssertFalse(rules.validate(.object([:]), actionID: "shell.run").isEmpty, "script is required")
        XCTAssertFalse(rules.validate(.object(["script": .string("  ")]), actionID: "shell.run").isEmpty)
    }

    func testShellRequestsOutputLimit() async throws {
        let action = ShellRunAction(process: fakes.process)
        _ = try await action.run(context(action, ["script": .string("x")]))
        XCTAssertEqual(fakes.process.requests.first?.outputLimit, 64 * 1024)
    }

    // MARK: shortcut.run

    func testShortcutRunsViaCLI() async throws {
        let action = ShortcutRunAction(process: fakes.process)
        _ = try await action.run(context(action, ["name": .string("My Shortcut")]))
        let request = try XCTUnwrap(fakes.process.requests.first)
        XCTAssertEqual(request.executable, "/usr/bin/shortcuts")
        XCTAssertEqual(request.arguments, ["run", "My Shortcut"])
    }

    func testShortcutFailureShowsCLIError() async {
        fakes.process.result = ProcessResult(exitStatus: 1, stderr: "Error: Couldn’t find shortcut “Nope”\n")
        let action = ShortcutRunAction(process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, ["name": .string("Nope")])) }
        XCTAssertEqual(message, "Shortcut “Nope”: Error: Couldn’t find shortcut “Nope”", "the CLI error is localized and does not name the shortcut, so the name is added")
    }

    func testShortcutFailureWithoutStderrStillNamesIt() async {
        fakes.process.result = ProcessResult(exitStatus: 1)
        let action = ShortcutRunAction(process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, ["name": .string("Nope")])) }
        XCTAssertEqual(message, "Shortcut “Nope” exited with status 1")
    }

    func testShortcutNeedsAName() {
        let action = ShortcutRunAction(process: fakes.process)
        XCTAssertFalse(action.paramRules.validate(.object([:]), actionID: "shortcut.run").isEmpty)
        XCTAssertEqual(action.timeout(for: Params(.object([:]))), .seconds(60))
    }

    // MARK: dnd.toggle

    func testDoNotDisturbRunsTheNamedShortcut() async throws {
        let action = DoNotDisturbAction(process: fakes.process)
        _ = try await action.run(context(action, ["shortcut": .string("Focus Toggle")]))
        XCTAssertEqual(fakes.process.requests.first?.arguments, ["run", "Focus Toggle"])
    }

    func testDoNotDisturbHasADefaultShortcutName() async throws {
        let action = DoNotDisturbAction(process: fakes.process)
        _ = try await action.run(context(action, [:]))
        XCTAssertEqual(fakes.process.requests.first?.arguments, ["run", DoNotDisturbAction.defaultShortcutName])
        XCTAssertNil(action.isActive(params: Params(.object([:]))), "no public API to read Focus state")
    }

    // MARK: screen.lock

    func testLockUsesPrivateSymbolFirst() async throws {
        fakes.screenLocker.succeeds = true
        let action = ScreenLockAction(locker: fakes.screenLocker, process: fakes.process)
        _ = try await action.run(context(action, [:]))
        XCTAssertEqual(fakes.screenLocker.calls, 1)
        XCTAssertTrue(fakes.process.requests.isEmpty, "no fallback when the private call worked")
    }

    func testLockFallsBackToPmsetWhenSymbolUnavailable() async throws {
        fakes.screenLocker.succeeds = false
        let action = ScreenLockAction(locker: fakes.screenLocker, process: fakes.process)
        _ = try await action.run(context(action, [:]))
        let request = try XCTUnwrap(fakes.process.requests.first)
        XCTAssertEqual(request.executable, "/usr/bin/pmset")
        XCTAssertEqual(request.arguments, ["displaysleepnow"])
    }

    func testLockFallbackFailureIsReported() async {
        fakes.screenLocker.succeeds = false
        fakes.process.result = ProcessResult(exitStatus: 1, stderr: "pmset: nope")
        let action = ScreenLockAction(locker: fakes.screenLocker, process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, [:])) }
        XCTAssertEqual(message, "pmset: nope")
    }

    // MARK: appearance.toggle

    func testDarkModeTogglesFromLightToDark() async throws {
        fakes.appearance.isDark = false
        let action = AppearanceToggleAction(appearance: fakes.appearance, process: fakes.process)
        _ = try await action.run(context(action, [:]))
        let request = try XCTUnwrap(fakes.process.requests.first)
        XCTAssertEqual(request.executable, "/usr/bin/osascript")
        XCTAssertEqual(request.arguments.first, "-e")
        XCTAssertTrue(request.arguments[1].contains("System Events"))
        XCTAssertTrue(request.arguments[1].contains("dark mode to true"), request.arguments[1])
    }

    func testDarkModeTogglesFromDarkToLight() async throws {
        fakes.appearance.isDark = true
        let action = AppearanceToggleAction(appearance: fakes.appearance, process: fakes.process)
        _ = try await action.run(context(action, [:]))
        XCTAssertTrue(fakes.process.requests[0].arguments[1].contains("dark mode to false"))
    }

    func testDarkModeAutomationDenialGivesActionableMessage() async {
        fakes.process.result = ProcessResult(
            exitStatus: 1,
            stderr: "execution error: Not authorized to send Apple events to System Events. (-1743)\n"
        )
        let action = AppearanceToggleAction(appearance: fakes.appearance, process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, [:])) }
        XCTAssertTrue(message?.contains("Automation") == true, message ?? "nil")
        XCTAssertTrue(message?.contains("System Events") == true, message ?? "nil")
    }

    func testDarkModeOtherFailuresShowStderr() async {
        fakes.process.result = ProcessResult(exitStatus: 1, stderr: "execution error: something else (-50)")
        let action = AppearanceToggleAction(appearance: fakes.appearance, process: fakes.process)
        let message = await failureMessage { try await action.run(context(action, [:])) }
        XCTAssertEqual(message, "execution error: something else (-50)")
    }

    func testDarkModeStateAndPermission() {
        let action = AppearanceToggleAction(appearance: fakes.appearance, process: fakes.process)
        fakes.appearance.isDark = true
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), true)
        fakes.appearance.isDark = false
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), false)
        XCTAssertEqual(action.permissions, [.automationSystemEvents])
    }
}
