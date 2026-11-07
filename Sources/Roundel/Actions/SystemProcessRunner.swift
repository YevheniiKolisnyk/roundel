import Foundation
import RoundelCore

/// Runs child processes off the main thread. Cancelling the calling task terminates the process (SIGTERM, then
/// SIGKILL after two seconds). Output is read continuously so a chatty process cannot fill the pipe and hang.
struct SystemProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        let job = ProcessJob(request)
        return try await withTaskCancellationHandler {
            try await job.start()
        } onCancel: {
            job.cancel()
        }
    }
}

private final class ProcessJob: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let limit: Int

    private let lock = NSLock()
    private var cancelled = false
    private var started = false
    private var stdoutData = Data()
    private var stderrData = Data()
    private var truncated = false

    init(_ request: ProcessRequest) {
        limit = request.outputLimit
        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = request.arguments
        if let directory = request.workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func start() async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            if lock.withLock({ cancelled }) {
                continuation.resume(throwing: CancellationError())
                return
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.append(handle.availableData, toStdout: true)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.append(handle.availableData, toStdout: false)
            }
            process.terminationHandler = { [weak self] finished in
                self?.finish(finished, continuation)
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
                return
            }

            let cancelNow = lock.withLock { () -> Bool in
                started = true
                return cancelled
            }
            if cancelNow { terminate() }
        }
    }

    func cancel() {
        let running = lock.withLock { () -> Bool in
            cancelled = true
            return started
        }
        if running { terminate() }
    }

    private func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func append(_ data: Data, toStdout: Bool) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let used = toStdout ? stdoutData.count : stderrData.count
        let room = max(0, limit - used)
        if data.count > room { truncated = true }
        let slice = data.prefix(room)
        if toStdout { stdoutData.append(slice) } else { stderrData.append(slice) }
    }

    private func finish(_ finished: Process, _ continuation: CheckedContinuation<ProcessResult, Error>) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // A background child of the script may still hold the pipe open, so drain without blocking.
        append(Self.drain(stdoutPipe.fileHandleForReading), toStdout: true)
        append(Self.drain(stderrPipe.fileHandleForReading), toStdout: false)
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        let (wasCancelled, out, err, wasTruncated) = lock.withLock { (cancelled, stdoutData, stderrData, truncated) }
        if wasCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        continuation.resume(returning: ProcessResult(
            exitStatus: finished.terminationStatus,
            terminatedBySignal: finished.terminationReason == .uncaughtSignal,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            outputTruncated: wasTruncated
        ))
    }

    private static func drain(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}
