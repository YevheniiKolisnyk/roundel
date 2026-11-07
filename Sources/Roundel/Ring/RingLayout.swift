import CoreGraphics
import RoundelCore

/// Fixed visual metrics for milestone 1. Becomes configurable later.
enum RingLayout {
    static let deadZoneRadius: CGFloat = 30
    static let outerRadius: CGFloat = 124
    static let panelPadding: CGFloat = 4
    static var panelSide: CGFloat { (outerRadius + panelPadding) * 2 }

    static func geometry(sectionCount: Int) -> RingGeometry {
        RingGeometry(sectionCount: sectionCount, deadZoneRadius: deadZoneRadius, outerRadius: outerRadius)
    }
}
