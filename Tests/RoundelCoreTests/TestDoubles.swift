import Foundation
@testable import RoundelCore

// Fakes for the small OS-facing protocols. The real calls are never unit-tested.

@MainActor
final class FakeWorkspace: WorkspaceOpening {
    var bundleIDs: [String: URL] = [:]
    var existing: Set<String> = []
    var openedApps: [URL] = []
    var opened: [URL] = []
    var failure: String?

    func applicationURL(forBundleID id: String) -> URL? { bundleIDs[id] }
    func fileExists(at url: URL) -> Bool { existing.contains(url.path) }

    func openApplication(at url: URL) async throws {
        if let failure { throw ActionError.failed(failure) }
        openedApps.append(url)
    }

    func open(_ url: URL) async throws {
        if let failure { throw ActionError.failed(failure) }
        opened.append(url)
    }
}

final class FakeProcess: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [ProcessRequest] = []
    var result = ProcessResult(exitStatus: 0)
    var error: Error?
    var delay: Duration?
    private(set) var wasCancelled = false

    var requests: [ProcessRequest] { lock.withLock { _requests } }

    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        lock.withLock { _requests.append(request) }
        if let delay {
            do { try await Task.sleep(for: delay) } catch {
                lock.withLock { wasCancelled = true }
                throw error
            }
        }
        if let error { throw error }
        return result
    }
}

@MainActor
final class FakePower: PowerAssertionHolding {
    private(set) var isHeld = false
    private(set) var acquisitions: [(mode: SleepPreventionMode, reason: String, releaseAfter: TimeInterval?)] = []
    private(set) var releases = 0
    var failure: String?

    func acquire(mode: SleepPreventionMode, reason: String, releaseAfter: TimeInterval?) throws {
        if let failure { throw ActionError.failed(failure) }
        acquisitions.append((mode, reason, releaseAfter))
        isHeld = true
    }

    func release() {
        releases += 1
        isHeld = false
    }
}

@MainActor
final class FakeScreenLocker: ScreenLocking {
    var succeeds = true
    private(set) var calls = 0
    func lockImmediately() -> Bool { calls += 1; return succeeds }
}

@MainActor
final class FakeAppearance: AppearanceReading {
    var isDark = false
}

@MainActor
final class FakeMute: MuteControlling {
    var isMuted: Bool? = false
    private(set) var sets: [Bool] = []
    var failure: String?

    func setMuted(_ muted: Bool) throws {
        if let failure { throw ActionError.failed(failure) }
        sets.append(muted)
        isMuted = muted
    }
}

@MainActor
final class FakeMedia: MediaKeySending {
    private(set) var sent: [MediaKey] = []
    func send(_ key: MediaKey) { sent.append(key) }
}

@MainActor
final class FakePermissions: PermissionChecking {
    var statuses: [Permission: PermissionStatus] = [:]
    private(set) var requested: [Permission] = []
    func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .granted }
    func request(_ permission: Permission) { requested.append(permission) }
}

final class FakeLogger: ActionLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var _infos: [String] = []
    var infos: [String] { lock.withLock { _infos } }
    func info(_ message: String) { lock.withLock { _infos.append(message) } }
    func warning(_ message: String) { lock.withLock { _infos.append("WARNING: " + message) } }
}

@MainActor
final class FakeReporter: ActionReporting {
    private(set) var infos: [String] = []
    private(set) var warnings: [String] = []
    private(set) var toasts: [(message: String, isError: Bool)] = []
    func info(_ message: String) { infos.append(message) }
    func warning(_ message: String) { warnings.append(message) }
    func toast(_ message: String, isError: Bool) { toasts.append((message, isError)) }
}

/// A bundle of fakes wired into `ActionServices`, with typed access for assertions.
@MainActor
struct Fakes {
    let workspace = FakeWorkspace()
    let process = FakeProcess()
    let power = FakePower()
    let screenLocker = FakeScreenLocker()
    let appearance = FakeAppearance()
    let mute = FakeMute()
    let media = FakeMedia()
    let selectedText = FakeSelectedText()
    let inputSources = FakeInputSources()
    let logger = FakeLogger()

    var services: ActionServices {
        ActionServices(workspace: workspace, process: process, power: power, screenLocker: screenLocker,
                       appearance: appearance, mute: mute, media: media, selectedText: selectedText,
                       inputSources: inputSources, logger: logger)
    }
}

/// A configurable action for executor tests.
struct StubAction: Action {
    var id = "stub.action"
    var title = "Stub"
    var defaultIcon: Icon = .symbol("star")
    var paramRules = ParamRules(specs: [])
    var permissions: Set<Permission> = []
    var timeoutValue: Duration = .seconds(5)
    var behavior: @Sendable () async throws -> ActionResult = { .done }

    func timeout(for params: Params) -> Duration { timeoutValue }
    func run(_ context: ActionContext) async throws -> ActionResult { try await behavior() }
}

func node(_ id: String, action: String = "stub.action", params: JSONValue = .object([:])) -> ActionNode {
    ActionNode(id: id, title: "Node \(id)", action: action, params: params)
}
