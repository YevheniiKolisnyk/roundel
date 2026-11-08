import Foundation

/// How many images are processed at once. Three, as long as together they stay within a pixel budget (a 50-megapixel
/// photo decodes to about 200 MB, and the encoder holds a second copy); a bigger one runs alone.
public struct ConcurrencyPlan: Equatable, Sendable {
    public static let standard = ConcurrencyPlan(maxConcurrent: 3, pixelBudget: 50_000_000)

    public let maxConcurrent: Int
    public let pixelBudget: Int

    public init(maxConcurrent: Int, pixelBudget: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.pixelBudget = max(1, pixelBudget)
    }

    /// May a job of `next` pixels start while jobs of `runningPixels` are running? Alone, a job always may.
    public func canStart(runningPixels: [Int], next: Int) -> Bool {
        if runningPixels.isEmpty { return true }
        guard runningPixels.count < maxConcurrent else { return false }
        return runningPixels.reduce(0, +) + max(next, 0) <= pixelBudget
    }
}

/// Runs numbered jobs under a `ConcurrencyPlan`, starting them in order, and gives their results back in order.
enum BatchRunner {
    /// - Parameters:
    ///   - weight: the pixels job `index` holds in memory; asked once, when the job is about to start.
    ///   - progress: called once per finished job with `(done, total)`.
    /// - Returns: one entry per job; `nil` only if the job never ran (cancelled).
    static func run<R: Sendable>(count total: Int, plan: ConcurrencyPlan, weight: @escaping @Sendable (Int) -> Int,
                                 work: @escaping @Sendable (Int) async -> R, progress: @escaping @Sendable (Int, Int) -> Void) async -> [R?] {
        guard total > 0 else { return [] }
        var results = [R?](repeating: nil, count: total)
        var running: [Int: Int] = [:]   // job -> pixels
        var next = 0
        var done = 0

        await withTaskGroup(of: (Int, R).self) { group in
            func startWhatFits() {
                while next < total, !Task.isCancelled {
                    let pixels = weight(next)
                    guard plan.canStart(runningPixels: Array(running.values), next: pixels) else { return }
                    let index = next
                    next += 1
                    running[index] = pixels
                    group.addTask { (index, await work(index)) }
                }
            }
            startWhatFits()
            while let (index, result) = await group.next() {
                results[index] = result
                running[index] = nil
                done += 1
                progress(done, total)
                startWhatFits()
            }
        }
        return results
    }
}
