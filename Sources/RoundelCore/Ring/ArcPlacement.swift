import CoreGraphics
import Foundation

/// Keeps a child arc on screen by sliding it along its band, never so far that the parent section stops being
/// inside the arc (the connector must still reach it).
public enum ArcPlacement {
    public struct Context: Equatable, Sendable {
        /// Ring center in screen coordinates (y-up).
        public var ringCenter: CGPoint
        /// Usable screen area in the same coordinates (e.g. `NSScreen.visibleFrame`).
        public var bounds: CGRect

        public init(ringCenter: CGPoint, bounds: CGRect) {
            self.ringCenter = ringCenter
            self.bounds = bounds
        }
    }

    private static let stepDegrees = 0.5
    private static let samples = 20

    /// The angle (radians, clockwise from 12 o'clock) the arc's middle should face. Equals `desired` when the arc
    /// already fits; otherwise the closest placement with no part off screen, or, when none exists, the one with the
    /// least overflow.
    public static func centerAngle(
        desired: Double, sweep: Double, itemWidth: Double, innerRadius: Double, outerRadius: Double,
        ringCenter: CGPoint, bounds: CGRect, margin: Double
    ) -> Double {
        guard sweep < 2 * .pi - 1e-9 else { return desired }

        let safe = bounds.insetBy(dx: margin, dy: margin)
        func overflow(_ center: Double) -> Double {
            var total = 0.0
            for radius in [innerRadius, outerRadius] {
                for step in 0...samples {
                    let angle = center - sweep / 2 + sweep * Double(step) / Double(samples)
                    let x = Double(ringCenter.x) + radius * sin(angle)
                    let y = Double(ringCenter.y) + radius * cos(angle)
                    total += max(0, Double(safe.minX) - x) + max(0, x - Double(safe.maxX))
                    total += max(0, Double(safe.minY) - y) + max(0, y - Double(safe.maxY))
                }
            }
            return total
        }

        var best = desired
        var bestOverflow = overflow(desired)
        if bestOverflow == 0 { return desired }

        let maxShift = max(0, sweep / 2 - itemWidth / 2)
        let step = stepDegrees * .pi / 180
        var shifts: [Double] = []
        var shift = step
        while shift < maxShift { shifts.append(shift); shift += step }
        if maxShift > 0 { shifts.append(maxShift) }

        for shift in shifts {
            for candidate in [desired + shift, desired - shift] {   // clockwise first on a tie
                let value = overflow(candidate)
                if value == 0 { return candidate }
                if value < bestOverflow - 1e-9 {
                    best = candidate
                    bestOverflow = value
                }
            }
        }
        return best
    }
}
