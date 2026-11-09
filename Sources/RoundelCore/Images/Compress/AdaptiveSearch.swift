import Foundation
import CoreGraphics

/// Strong's search for the lowest quality that still looks the same as the original.
///
/// This deliberately replaces the earlier rule "no SSIM at run time": a fixed quality has to be chosen for the worst picture
/// (a heavily textured one) and wastes a third of the savings on every smooth one. Here every Strong file gets a few trial
/// encodes of a crop of about one megapixel, each scored with `ImageMetrics.similarity`, and then one full encode at the
/// quality that passed. The search is bounded and deterministic: at most `maxTrials` trials, qualities on a whole-percent grid,
/// a fixed bisection, hard floors per format (the range's lower end), and a time budget per file that only matters for a
/// pathologically slow encoder (then the fixed worst-case-safe number is used).
public enum AdaptiveSearch {
    /// The score a trial must reach: `min(luma SSIM, mean RGB SSIM)`.
    public static let target = 0.88
    public static let maxTrials = 5
    /// The crop is at most this wide and this tall (about one megapixel).
    public static let cropSide = 1024

    /// Qualities in whole percent. The lower end is the floor: SSIM does not see blockiness or color noise, so no picture goes below it.
    public static let heicRange = 20...55
    public static let webpRange = 30...70
    /// JPEG's range ends at what the source's own quality allows (`JPEGQuality.cap`), so the file cannot grow.
    public static func range(forJPEG capPercent: Int?) -> ClosedRange<Int> {
        let upper = min(55, capPercent ?? 55)
        return min(30, upper)...upper
    }

    public struct Outcome: Equatable, Sendable {
        /// The quality to encode with, in percent.
        public var quality: Int
        /// Trials that finished (a trial that could not be evaluated does not count).
        public var completedTrials: Int
        /// A quality that reached the target was found.
        public var reachedTarget: Bool
        /// A trial could not be run (out of time, an encoder error): the answer is the best known, not the best possible.
        public var stoppedEarly: Bool
    }

    /// - Parameter passes: encodes at the given quality and says whether the result reaches the target; `nil` if that could not be
    ///   done (the search then stops).
    /// - Returns: the lowest passing quality it could establish; the top of the range if even that misses the target or nothing
    ///   could be evaluated.
    public static func search(range: ClosedRange<Int>, maxTrials: Int = AdaptiveSearch.maxTrials, passes: (Int) -> Bool?) -> Outcome {
        let lo = range.lowerBound, hi = range.upperBound
        var completed = 0
        func outcome(_ quality: Int, reached: Bool, stopped: Bool = false) -> Outcome {
            Outcome(quality: quality, completedTrials: completed, reachedTarget: reached, stoppedEarly: stopped)
        }

        guard let first = passes(lo) else { return outcome(hi, reached: false, stopped: true) }
        completed += 1
        if first { return outcome(lo, reached: true) }
        if lo == hi { return outcome(hi, reached: false) }

        guard completed < maxTrials, let second = passes(hi) else { return outcome(hi, reached: false, stopped: true) }
        completed += 1
        if !second { return outcome(hi, reached: false) }

        var low = lo, high = hi
        while completed < maxTrials, high - low > 1 {
            let middle = (low + high) / 2
            guard let ok = passes(middle) else { return outcome(high, reached: true, stopped: true) }
            completed += 1
            if ok { high = middle } else { low = middle }
        }
        return outcome(high, reached: true)
    }

    /// The part of the picture the trials work on: the middle, at most `cropSide` square; the whole picture if it is smaller.
    public static func cropRect(width: Int, height: Int) -> CGRect {
        let w = min(width, cropSide), h = min(height, cropSide)
        return CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}
