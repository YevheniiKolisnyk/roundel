import Foundation

// Small protocols in front of every OS call, so actions are testable with fakes. The real implementations
// live in the app target; they are not unit-tested.

@MainActor
public protocol WorkspaceOpening {
    func applicationURL(forBundleID id: String) -> URL?
    func fileExists(at url: URL) -> Bool
    func openApplication(at url: URL) async throws
    func open(_ url: URL) async throws
    /// Opens the files with that application.
    func open(_ urls: [URL], withApplicationAt appURL: URL) async throws
}

public struct ProcessRequest: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: String?
    /// Each of stdout and stderr is capped at this many bytes.
    public var outputLimit: Int

    public init(executable: String, arguments: [String] = [], workingDirectory: String? = nil, outputLimit: Int = 64 * 1024) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.outputLimit = outputLimit
    }
}

public struct ProcessResult: Equatable, Sendable {
    /// Exit code, or the signal number when `terminatedBySignal`.
    public var exitStatus: Int32
    public var terminatedBySignal: Bool
    public var stdout: String
    public var stderr: String
    public var outputTruncated: Bool

    public init(exitStatus: Int32, terminatedBySignal: Bool = false, stdout: String = "", stderr: String = "", outputTruncated: Bool = false) {
        self.exitStatus = exitStatus
        self.terminatedBySignal = terminatedBySignal
        self.stdout = stdout
        self.stderr = stderr
        self.outputTruncated = outputTruncated
    }
}

/// Runs a child process off the main thread. Cancelling the calling task must kill the process.
public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}

public enum SleepPreventionMode: String, Sendable {
    /// Keeps the display on (and so the Mac awake).
    case display
    /// Lets the display sleep but keeps the Mac awake.
    case system
}

@MainActor
public protocol PowerAssertionHolding {
    var isHeld: Bool { get }
    func acquire(mode: SleepPreventionMode, reason: String, releaseAfter: TimeInterval?) throws
    func release()
}

@MainActor
public protocol ScreenLocking {
    /// Locks immediately via the private login-framework symbol. Returns false when it is unavailable.
    func lockImmediately() -> Bool
}

@MainActor
public protocol AppearanceReading {
    var isDark: Bool { get }
}

@MainActor
public protocol MuteControlling {
    /// `nil` when the current output device has no mute control.
    var isMuted: Bool? { get }
    func setMuted(_ muted: Bool) throws
}

public enum MediaKey: Sendable {
    case playPause, next, previous
}

@MainActor
public protocol MediaKeySending {
    func send(_ key: MediaKey)
}

@MainActor
public protocol PermissionChecking {
    func status(of permission: Permission) -> PermissionStatus
    /// Shows the system prompt or opens the right System Settings pane.
    func request(_ permission: Permission)
}

public protocol ActionLogging: Sendable {
    func info(_ message: String)
    func warning(_ message: String)
}

/// How the executor talks to the user: log lines and toasts.
@MainActor
public protocol ActionReporting {
    func info(_ message: String)
    func warning(_ message: String)
    func toast(_ message: String, isError: Bool)
    /// A running action's status ("Converting 4/10"). Replaces the previous one; not logged line by line.
    func progress(_ message: String)
}

public extension ActionReporting {
    func progress(_ message: String) {}
}

public struct ActionServices: Sendable {
    public var workspace: any WorkspaceOpening
    public var process: any ProcessRunning
    public var power: any PowerAssertionHolding
    public var screenLocker: any ScreenLocking
    public var appearance: any AppearanceReading
    public var mute: any MuteControlling
    public var media: any MediaKeySending
    public var selectedText: any SelectedTextServing
    public var inputSources: any InputSourceSwitching
    public var imageConverter: any ImageConverting
    public var imageCapabilities: any ImageCapabilities
    public var logger: any ActionLogging

    public init(workspace: any WorkspaceOpening, process: any ProcessRunning, power: any PowerAssertionHolding,
                screenLocker: any ScreenLocking, appearance: any AppearanceReading, mute: any MuteControlling,
                media: any MediaKeySending, selectedText: any SelectedTextServing, inputSources: any InputSourceSwitching,
                imageConverter: any ImageConverting, imageCapabilities: any ImageCapabilities, logger: any ActionLogging) {
        self.workspace = workspace
        self.process = process
        self.power = power
        self.screenLocker = screenLocker
        self.appearance = appearance
        self.mute = mute
        self.media = media
        self.selectedText = selectedText
        self.inputSources = inputSources
        self.imageConverter = imageConverter
        self.imageCapabilities = imageCapabilities
        self.logger = logger
    }
}
