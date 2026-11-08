import SwiftUI

/// An annular sector with rounded corners (the root ring is the full-circle case: an annulus). Angles are radians
/// clockwise from 12 o'clock, the same convention as `RingGeometry`. This is only how a band or a highlight is drawn;
/// hit-testing stays polar and never looks at this shape.
///
/// The corners are true circular fillets: each is tangent to the radial edge and to the arc, so the outline is
/// smooth. A radius too big for the shape is reduced until it fits instead of distorting the outline.
struct RingBandShape: InsettableShape {
    var innerRadius: Double
    var outerRadius: Double
    var startAngle: Double
    var endAngle: Double
    var cornerRadius: Double
    var isFullCircle = false

    /// Largest distance between the true arc and the polyline that stands for it.
    private static let flatness = 0.05

    func path(in rect: CGRect) -> Path {
        guard outerRadius > innerRadius, outerRadius > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if isFullCircle { return annulus(center: center) }

        let sweep = endAngle - startAngle
        guard sweep > 1e-6 else { return Path() }

        let thickness = outerRadius - innerRadius
        let fitsSweep = innerRadius * sin(min(sweep / 2, .pi / 2))
        let radius = max(0, min(cornerRadius, thickness / 2 - 0.01, fitsSweep))

        var points: [CGPoint] = []
        if radius < 0.05 {
            points += arc(center, outerRadius, startAngle, endAngle)
            points += arc(center, innerRadius, endAngle, startAngle)
        } else {
            let dOuter = outerRadius - radius, dInner = innerRadius + radius
            let tiltOuter = asin(radius / dOuter), tiltInner = asin(radius / dInner)
            let lineOuter = (dOuter * dOuter - radius * radius).squareRoot()
            let lineInner = (dInner * dInner - radius * radius).squareRoot()
            let a0 = startAngle, a1 = endAngle

            points.append(polar(center, lineInner, a0))
            // Outer start corner, outer arc, outer end corner.
            points += fillet(around: polar(center, dOuter, a0 + tiltOuter), from: polar(center, lineOuter, a0), to: polar(center, outerRadius, a0 + tiltOuter))
            points += arc(center, outerRadius, a0 + tiltOuter, a1 - tiltOuter)
            points += fillet(around: polar(center, dOuter, a1 - tiltOuter), from: polar(center, outerRadius, a1 - tiltOuter), to: polar(center, lineOuter, a1))
            // Inner end corner, inner arc back, inner start corner.
            points += fillet(around: polar(center, dInner, a1 - tiltInner), from: polar(center, lineInner, a1), to: polar(center, innerRadius, a1 - tiltInner))
            points += arc(center, innerRadius, a1 - tiltInner, a0 + tiltInner)
            points += fillet(around: polar(center, dInner, a0 + tiltInner), from: polar(center, innerRadius, a0 + tiltInner), to: polar(center, lineInner, a0))
        }

        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    /// The shape pulled in by `amount` on every side (rims and ends), with its corner radius reduced to stay concentric.
    func inset(by amount: CGFloat) -> RingBandShape {
        let d = Double(amount)
        let mid = max(1, (innerRadius + outerRadius) / 2)
        var shape = self
        shape.innerRadius = innerRadius + d
        shape.outerRadius = outerRadius - d
        if !isFullCircle {
            shape.startAngle = startAngle + d / mid
            shape.endAngle = endAngle - d / mid
        }
        shape.cornerRadius = max(0, cornerRadius - d)
        return shape
    }

    // MARK: Outline pieces

    private func annulus(center: CGPoint) -> Path {
        var path = Path()
        path.addLines(arc(center, outerRadius, 0, 2 * .pi))
        path.closeSubpath()
        if innerRadius > 0 {
            path.addLines(arc(center, innerRadius, 2 * .pi, 0))   // opposite direction: a hole under the nonzero rule
            path.closeSubpath()
        }
        return path
    }

    /// Points along a circle from `from` to `to` (either direction), both ends included.
    private func arc(_ center: CGPoint, _ radius: Double, _ from: Double, _ to: Double) -> [CGPoint] {
        let step = radius > Self.flatness ? max(0.01, 2 * acos(1 - Self.flatness / radius)) : .pi
        let count = max(1, Int((abs(to - from) / step).rounded(.up)))
        return (0...count).map { polar(center, radius, from + (to - from) * Double($0) / Double(count)) }
    }

    /// Points along the quarter circle around `center` from `from` to `to` (the shorter way), end included.
    private func fillet(around center: CGPoint, from: CGPoint, to: CGPoint) -> [CGPoint] {
        let radius = hypot(from.x - center.x, from.y - center.y)
        let a = atan2(from.y - center.y, from.x - center.x)
        let b = atan2(to.y - center.y, to.x - center.x)
        let delta = atan2(sin(b - a), cos(b - a))
        let count = max(2, Int((abs(delta) / max(0.01, 2 * acos(1 - Self.flatness / max(radius, Self.flatness)))).rounded(.up)))
        return (1...count).map { index in
            let angle = a + delta * Double(index) / Double(count)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    private func polar(_ center: CGPoint, _ radius: Double, _ angle: Double) -> CGPoint {
        WedgeShape.point(center: center, radius: radius, angle: angle)
    }
}
