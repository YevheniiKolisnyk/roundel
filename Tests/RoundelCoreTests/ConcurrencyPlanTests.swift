import XCTest
@testable import RoundelCore

/// How many images may be processed at once: three, unless together they would need too much memory.
final class ConcurrencyPlanTests: XCTestCase {
    private let plan = ConcurrencyPlan.standard
    private let mp = 1_000_000

    func testTheStandardLimits() {
        XCTAssertEqual(plan.maxConcurrent, 3)
        XCTAssertEqual(plan.pixelBudget, 50 * mp)
    }

    func testSmallImagesRunThreeAtATime() {
        XCTAssertTrue(plan.canStart(runningPixels: [], next: 12 * mp))
        XCTAssertTrue(plan.canStart(runningPixels: [12 * mp], next: 12 * mp))
        XCTAssertTrue(plan.canStart(runningPixels: [12 * mp, 12 * mp], next: 12 * mp))
        XCTAssertFalse(plan.canStart(runningPixels: [1, 1, 1], next: 1), "never more than three")
    }

    func testTheBudgetIsInclusiveAndCountsTheNewcomer() {
        XCTAssertTrue(plan.canStart(runningPixels: [30 * mp], next: 20 * mp), "exactly 50 MP is allowed")
        XCTAssertFalse(plan.canStart(runningPixels: [30 * mp], next: 20 * mp + 1))
        XCTAssertFalse(plan.canStart(runningPixels: [25 * mp, 20 * mp], next: 6 * mp))
    }

    func testAHugeImageAlwaysRunsAloneButAlwaysRuns() {
        XCTAssertTrue(plan.canStart(runningPixels: [], next: 200 * mp), "alone it must be allowed or it would never run")
        XCTAssertFalse(plan.canStart(runningPixels: [1 * mp], next: 200 * mp), "waits for the small one to finish")
        XCTAssertFalse(plan.canStart(runningPixels: [200 * mp], next: 1 * mp), "nothing starts beside a huge one")
        XCTAssertFalse(plan.canStart(runningPixels: [60 * mp], next: 0))
    }

    func testAnUnknownSizeCountsAsNothingButStillObeysTheCountLimit() {
        XCTAssertTrue(plan.canStart(runningPixels: [40 * mp], next: 0))
        XCTAssertFalse(plan.canStart(runningPixels: [0, 0, 0], next: 0))
    }

    func testAnOddPlanIsRepaired() {
        XCTAssertEqual(ConcurrencyPlan(maxConcurrent: 0, pixelBudget: -5).maxConcurrent, 1)
        XCTAssertTrue(ConcurrencyPlan(maxConcurrent: 0, pixelBudget: -5).canStart(runningPixels: [], next: 10))
    }
}

final class BatchRunnerTests: XCTestCase {
    private let mp = 1_000_000

    /// Runs `weights.count` fake jobs that each take a moment, and records how many ran together and how many pixels.
    private func run(weights: [Int], plan: ConcurrencyPlan = .standard) async -> (peakCount: Int, peakPixels: Int, results: [Int?], progress: [Int]) {
        let recorder = Recorder()
        let progress = ProgressLog()
        let results = await BatchRunner.run(count: weights.count, plan: plan, weight: { weights[$0] }, work: { index -> Int in
            await recorder.start(weights[index])
            try? await Task.sleep(for: .milliseconds(30))
            await recorder.finish(weights[index])
            return index * 10
        }, progress: { done, _ in progress.add(done) })
        return (await recorder.peakCount, await recorder.peakPixels, results, progress.values)
    }

    func testResultsComeBackInInputOrderAndProgressCountsUp() async {
        let r = await run(weights: Array(repeating: 1 * mp, count: 8))
        XCTAssertEqual(r.results, (0..<8).map { $0 * 10 })
        XCTAssertEqual(r.progress, Array(1...8))
    }

    func testSmallImagesUseAllThreeSlots() async {
        let r = await run(weights: Array(repeating: 5 * mp, count: 9))
        XCTAssertEqual(r.peakCount, 3)
    }

    func testHugeImagesRunOneAtATime() async {
        let r = await run(weights: Array(repeating: 80 * mp, count: 4))
        XCTAssertEqual(r.peakCount, 1)
        XCTAssertEqual(r.results.compactMap { $0 }.count, 4, "all of them still run")
    }

    func testTheBudgetHoldsForAMix() async {
        let r = await run(weights: [30 * mp, 30 * mp, 5 * mp, 5 * mp, 5 * mp, 30 * mp, 20 * mp, 20 * mp])
        XCTAssertLessThanOrEqual(r.peakPixels, 50 * mp)
        XCTAssertLessThanOrEqual(r.peakCount, 3)
        XCTAssertEqual(r.results.compactMap { $0 }.count, 8)
    }

    func testAnEmptyBatchIsEmpty() async {
        let r = await run(weights: [])
        XCTAssertEqual(r.results.count, 0)
    }
}

private actor Recorder {
    var count = 0, pixels = 0, peakCount = 0, peakPixels = 0
    func start(_ weight: Int) { count += 1; pixels += weight; peakCount = max(peakCount, count); peakPixels = max(peakPixels, pixels) }
    func finish(_ weight: Int) { count -= 1; pixels -= weight }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int] = []
    var values: [Int] { lock.withLock { _values } }
    func add(_ v: Int) { lock.withLock { _values.append(v) } }
}
