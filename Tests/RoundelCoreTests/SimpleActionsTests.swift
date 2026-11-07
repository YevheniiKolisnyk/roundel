import XCTest
@testable import RoundelCore

@MainActor
final class SimpleActionsTests: XCTestCase {
    private let fakes = Fakes()

    private func context(_ params: [String: JSONValue] = [:]) -> ActionContext {
        ActionContext(nodeID: "n", title: "Node", params: Params(.object(params)))
    }

    private func failureMessage(_ block: () async throws -> ActionResult) async -> String? {
        do { _ = try await block(); return nil } catch let error as ActionError { return error.message } catch { return "\(error)" }
    }

    // MARK: app.open

    func testOpenAppByBundleId() async throws {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        fakes.workspace.bundleIDs["com.apple.Safari"] = url
        let action = AppOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["bundleId": .string("com.apple.Safari")]))
        XCTAssertEqual(fakes.workspace.openedApps, [url])
    }

    func testOpenAppByNameSearchesStandardFolders() async throws {
        fakes.workspace.existing = ["/System/Applications/Calculator.app"]
        let action = AppOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["name": .string("Calculator")]))
        XCTAssertEqual(fakes.workspace.openedApps.map(\.path), ["/System/Applications/Calculator.app"])
    }

    func testOpenAppByNameIgnoresAppSuffixAndChecksHomeApplications() async throws {
        fakes.workspace.existing = [NSHomeDirectory() + "/Applications/Tool.app"]
        let action = AppOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["name": .string("  Tool.app ")]))
        XCTAssertEqual(fakes.workspace.openedApps.map(\.path), [NSHomeDirectory() + "/Applications/Tool.app"])
    }

    func testOpenAppPrefersEarlierFolders() async throws {
        fakes.workspace.existing = ["/Applications/Foo.app", "/System/Applications/Foo.app"]
        let action = AppOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["name": .string("Foo")]))
        XCTAssertEqual(fakes.workspace.openedApps.map(\.path), ["/Applications/Foo.app"])
    }

    func testOpenAppNotFound() async {
        let action = AppOpenAction(workspace: fakes.workspace)
        let byName = await failureMessage { try await action.run(context(["name": .string("Nope")])) }
        XCTAssertEqual(byName, "application “Nope” not found")
        let byID = await failureMessage { try await action.run(context(["bundleId": .string("x.y")])) }
        XCTAssertEqual(byID, "no application with bundle id “x.y”")
    }

    func testOpenAppParamRules() {
        let rules = AppOpenAction(workspace: fakes.workspace).paramRules
        XCTAssertFalse(rules.validate(.object([:]), actionID: "app.open").isEmpty)
        XCTAssertFalse(rules.validate(.object(["name": .string("a"), "bundleId": .string("b")]), actionID: "app.open").isEmpty)
        XCTAssertTrue(rules.validate(.object(["name": .string("a")]), actionID: "app.open").isEmpty)
    }

    func testOpenAppNameMustNotBeAPath() {
        let action = AppOpenAction(workspace: fakes.workspace)
        let issues = action.extraValidation(Params(.object(["name": .string("../Evil")])))
        XCTAssertEqual(issues.filter(\.blocksRun).count, 1)
    }

    // MARK: url.open

    func testOpenURL() async throws {
        let action = URLOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["url": .string("https://example.com/a?b=1")]))
        XCTAssertEqual(fakes.workspace.opened.map(\.absoluteString), ["https://example.com/a?b=1"])
    }

    func testOpenURLAcceptsOtherSchemes() async throws {
        let action = URLOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["url": .string("mailto:a@b.c")]))
        XCTAssertEqual(fakes.workspace.opened.first?.scheme, "mailto")
    }

    func testOpenURLNeedsAScheme() async {
        let action = URLOpenAction(workspace: fakes.workspace)
        XCTAssertEqual(action.extraValidation(Params(.object(["url": .string("example.com")]))).filter(\.blocksRun).count, 1)
        XCTAssertTrue(action.extraValidation(Params(.object(["url": .string("https://example.com")]))).isEmpty)
        let message = await failureMessage { try await action.run(context(["url": .string("example.com")])) }
        XCTAssertNotNil(message)
        XCTAssertTrue(fakes.workspace.opened.isEmpty)
    }

    func testOpenURLFailureIsReported() async {
        fakes.workspace.failure = "no handler"
        let action = URLOpenAction(workspace: fakes.workspace)
        let message = await failureMessage { try await action.run(context(["url": .string("https://x.y")])) }
        XCTAssertEqual(message, "no handler")
    }

    // MARK: path.open

    func testOpenPathExpandsTilde() async throws {
        fakes.workspace.existing = [NSHomeDirectory() + "/Downloads"]
        let action = PathOpenAction(workspace: fakes.workspace)
        _ = try await action.run(context(["path": .string("~/Downloads")]))
        XCTAssertEqual(fakes.workspace.opened.map(\.path), [NSHomeDirectory() + "/Downloads"])
    }

    func testOpenPathMissingFile() async {
        let action = PathOpenAction(workspace: fakes.workspace)
        let message = await failureMessage { try await action.run(context(["path": .string("/no/such/thing")])) }
        XCTAssertEqual(message, "path not found: /no/such/thing")
        XCTAssertTrue(fakes.workspace.opened.isEmpty)
    }

    // MARK: caffeinate.toggle

    func testCaffeinateTurnsOnThenOff() async throws {
        let action = CaffeinateAction(power: fakes.power)
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), false)

        let on = try await action.run(context())
        XCTAssertEqual(fakes.power.acquisitions.count, 1)
        XCTAssertEqual(fakes.power.acquisitions[0].mode, .display)
        XCTAssertNil(fakes.power.acquisitions[0].releaseAfter)
        XCTAssertEqual(on, .message("Caffeinate on (keeps the display awake)"))
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), true)

        let off = try await action.run(context())
        XCTAssertEqual(fakes.power.releases, 1)
        XCTAssertEqual(off, .message("Caffeinate off"))
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), false)
    }

    func testCaffeinateModeAndDuration() async throws {
        let action = CaffeinateAction(power: fakes.power)
        let result = try await action.run(context(["mode": .string("system"), "minutes": .number(30)]))
        XCTAssertEqual(fakes.power.acquisitions[0].mode, .system)
        XCTAssertEqual(fakes.power.acquisitions[0].releaseAfter, 1800)
        XCTAssertEqual(result, .message("Caffeinate on for 30 min (keeps the Mac awake)"))
        XCTAssertFalse(fakes.power.acquisitions[0].reason.isEmpty)
    }

    func testCaffeinateFailure() async {
        fakes.power.failure = "IOReturn -1"
        let action = CaffeinateAction(power: fakes.power)
        let message = await failureMessage { try await action.run(context()) }
        XCTAssertEqual(message, "IOReturn -1")
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), false)
    }

    // MARK: media keys

    func testMediaActionsSendTheRightKeyAndNeedAccessibility() async throws {
        let cases: [(any Action, MediaKey)] = [
            (MediaPlayPauseAction(media: fakes.media), .playPause),
            (MediaNextAction(media: fakes.media), .next),
            (MediaPreviousAction(media: fakes.media), .previous),
        ]
        for (action, key) in cases {
            _ = try await action.run(context())
            XCTAssertEqual(fakes.media.sent.last, key, action.id)
            XCTAssertEqual(action.permissions, [.accessibility], action.id)
        }
        XCTAssertEqual(fakes.media.sent, [.playPause, .next, .previous])
    }

    // MARK: volume.muteToggle

    func testMuteToggles() async throws {
        let action = MuteToggleAction(mute: fakes.mute)
        fakes.mute.isMuted = false
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), false)
        _ = try await action.run(context())
        XCTAssertEqual(fakes.mute.sets, [true])
        XCTAssertEqual(action.isActive(params: Params(.object([:]))), true)
        _ = try await action.run(context())
        XCTAssertEqual(fakes.mute.sets, [true, false])
    }

    func testMuteUnsupportedDevice() async {
        fakes.mute.isMuted = nil
        let action = MuteToggleAction(mute: fakes.mute)
        let message = await failureMessage { try await action.run(context()) }
        XCTAssertEqual(message, "the current output device does not support mute")
        XCTAssertNil(action.isActive(params: Params(.object([:]))), "no indicator when unsupported")
    }

    // MARK: log

    func testLogActionWritesTheMessage() async throws {
        let action = LogAction(logger: fakes.logger)
        _ = try await action.run(context(["message": .string("hello")]))
        XCTAssertTrue(fakes.logger.infos.contains { $0.contains("hello") })
    }

    func testLogActionWithoutMessageStillWorks() async throws {
        let action = LogAction(logger: fakes.logger)
        XCTAssertTrue(action.paramRules.validate(.object([:]), actionID: "log").isEmpty)
        _ = try await action.run(context())
    }
}
