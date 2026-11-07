import Foundation

struct ActionTimeoutError: Error {
    let duration: Duration
}

/// Runs `operation` and gives up after `timeout`: the operation is cancelled and the caller gets `ActionTimeoutError`
/// right away, even if the operation is slow to notice the cancellation.
func raceWithTimeout<T: Sendable>(_ timeout: Duration, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let race = Race<T>(continuation)
        race.setTimer(Task.detached {
            do { try await Task.sleep(for: timeout) } catch { return }
            if race.finish(.failure(ActionTimeoutError(duration: timeout))) { race.cancelWork() }
        })
        race.setWork(Task.detached {
            let outcome: Result<T, Error>
            do { outcome = .success(try await operation()) } catch { outcome = .failure(error) }
            if race.finish(outcome) { race.cancelTimer() }
        })
    }
}

private final class Race<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var finished = false

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func setTimer(_ task: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        timer = task
        if finished { task.cancel() }
    }

    func setWork(_ task: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        work = task
        if finished { task.cancel() }
    }

    func cancelWork() { lock.withLock { work }?.cancel() }
    func cancelTimer() { lock.withLock { timer }?.cancel() }

    /// First caller wins and resumes the continuation; later callers get false.
    func finish(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        guard let continuation else { lock.unlock(); return false }
        self.continuation = nil
        finished = true
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}
