import SwiftUI

/// Annular sector. Angles are radians clockwise from 12 o'clock (same convention as `RingGeometry`).
struct WedgeShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = max(2, Int(((endAngle - startAngle) / (.pi / 36)).rounded(.up)))
        var path = Path()

        for step in 0...steps {
            let angle = startAngle + (endAngle - startAngle) * Double(step) / Double(steps)
            let point = Self.point(center: center, radius: outerRadius, angle: angle)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let angle = startAngle + (endAngle - startAngle) * Double(step) / Double(steps)
            path.addLine(to: Self.point(center: center, radius: innerRadius, angle: angle))
        }
        path.closeSubpath()
        return path
    }

    /// SwiftUI is y-down: clockwise-from-top angle θ maps to (sin θ, -cos θ).
    static func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }
}
