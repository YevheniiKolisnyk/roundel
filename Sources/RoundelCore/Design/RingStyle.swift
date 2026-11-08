import Foundation

/// What a ring item looks like right now.
public enum RingEmphasis: Equatable, Sendable {
    case none
    /// The group whose arc is open.
    case openParent
    /// The item under the pointer.
    case hovered
    /// An item that cannot be used now (dimmed): never highlighted, hover or not.
    case disabled
}

/// How strongly an emphasis is drawn.
public struct RingEmphasisTraits: Equatable, Sendable {
    public var showsHighlight: Bool
    public var fillOpacity: Double
    public var edgeOpacity: Double
    public var edgeWidth: Double
    /// Soft light just inside the edge.
    public var glowOpacity: Double
    public var iconOpacity: Double
    public var iconScale: Double
}

/// A highlight's place inside a band, in the ring's polar terms (angles clockwise from 12 o'clock, radians).
public struct HighlightGeometry: Equatable, Sendable {
    public var innerRadius: Double
    public var outerRadius: Double
    public var startAngle: Double
    public var endAngle: Double
    public var cornerRadius: Double
}

/// The look of the ring in numbers and small pure rules, like `RingMetrics` is for its geometry: separators, corner
/// radii, how strongly the selected item is drawn, how labels fit. Views take everything from here. Sizes and
/// hit-testing come from `RingMetrics` and are not affected by anything in this file.
public struct RingStyle: Equatable, Sendable {
    public static let standard = RingStyle()

    // Separators between items
    public var seamWidth = 1.0
    public var seamOpacity = 0.16
    /// Separators stop this far from the band's edges.
    public var seamInset = 10.0

    // Shapes
    /// Rounding of a band's outer corners (the ends of an arc, and every highlight's parent).
    public var bandCornerRadius = 14.0
    /// Space between a band's rim and a highlight inside it.
    public var highlightInset = 3.0
    /// Space between the highlights of two neighbouring items.
    public var itemGap = 2.0
    public var highlightCornerRadius: Double { max(0, bandCornerRadius - highlightInset) }

    // Emphasis
    public var dimmedOpacity = 0.4
    public var hoverIconScale = 1.1

    // Center indicator
    public var centerRingDiameter = 16.0
    public var centerRingWidth = 1.5
    public var centerRingOpacity = 0.45

    // Parent-to-arc stem
    public var connectorWidth = 3.0
    public var connectorOpacity = 0.5

    // The "this opens an arc" mark
    public var chevronSize = 10.0
    public var chevronOpacity = 0.6
    /// Distance from the band's outer edge to the chevron's center.
    public var chevronInset = 10.0

    // Labels (format names and the like) must fit their cell
    public var labelBaseSize = 12.0
    public var labelMinSize = 9.0
    public var labelPadding = 4.0

    // Appearing
    public var appearScale = 0.94
    public var arcAppearScale = 0.88

    public init() {}

    // MARK: Emphasis

    public func emphasis(isHovered: Bool, isOpenParent: Bool, isDisabled: Bool) -> RingEmphasis {
        if isDisabled { return .disabled }
        if isHovered { return .hovered }
        return isOpenParent ? .openParent : .none
    }

    /// The selected item must read at a glance on any wallpaper in either appearance: a strong accent fill, a light edge
    /// and a soft inner glow, never a fill alone. Increased Contrast pushes all three further. The open parent of a
    /// group is the same thing, more softly.
    public func traits(for emphasis: RingEmphasis, increaseContrast: Bool, isDark: Bool) -> RingEmphasisTraits {
        switch emphasis {
        case .hovered:
            return RingEmphasisTraits(
                showsHighlight: true,
                fillOpacity: increaseContrast ? (isDark ? 0.92 : 1.0) : (isDark ? 0.72 : 0.88),
                edgeOpacity: increaseContrast ? 0.9 : 0.55,
                edgeWidth: increaseContrast ? 2.0 : 1.0,
                glowOpacity: 0.30,
                iconOpacity: 1,
                iconScale: hoverIconScale
            )
        case .openParent:
            return RingEmphasisTraits(
                showsHighlight: true,
                fillOpacity: increaseContrast ? (isDark ? 0.5 : 0.55) : (isDark ? 0.34 : 0.40),
                edgeOpacity: increaseContrast ? 0.6 : 0.30,
                edgeWidth: increaseContrast ? 1.5 : 1.0,
                glowOpacity: 0.12,
                iconOpacity: 1,
                iconScale: 1
            )
        case .none:
            return RingEmphasisTraits(showsHighlight: false, fillOpacity: 0, edgeOpacity: 0, edgeWidth: 0, glowOpacity: 0, iconOpacity: 1, iconScale: 1)
        case .disabled:
            return RingEmphasisTraits(showsHighlight: false, fillOpacity: 0, edgeOpacity: 0, edgeWidth: 0, glowOpacity: 0, iconOpacity: dimmedOpacity, iconScale: 1)
        }
    }

    // MARK: Shapes

    /// The angle a separator of `width` points takes at `radius`, so it has the same width in points everywhere.
    public func seamAngle(width: Double, atRadius radius: Double) -> Double {
        radius > 0 ? width / radius : 0
    }

    /// A corner radius that fits a shape `thickness` points thick and `arcLength` points long: at most half of either,
    /// never negative.
    public func cornerRadius(thickness: Double, arcLength: Double, preferred: Double) -> Double {
        max(0, min(preferred, thickness / 2 - 0.5, arcLength / 2 - 0.5))
    }

    /// Where the highlight of item `index` of `band` goes: inset from the band's rim, with a small gap to its neighbours
    /// (and a larger inset from the rim at the ends of an arc), so highlights never touch each other or the edge.
    public func highlightGeometry(for band: RingBand, index: Int) -> HighlightGeometry {
        let inner = band.innerRadius + highlightInset
        let outer = band.outerRadius - highlightInset
        let mid = max(1, (inner + outer) / 2)

        let isFirst = index == 0, isLast = index == band.count - 1
        let leading = (isFirst && !band.isFullCircle) ? highlightInset : itemGap / 2
        let trailing = (isLast && !band.isFullCircle) ? highlightInset : itemGap / 2

        let itemStart = band.startAngle + Double(index) * band.itemWidth
        var start = itemStart + leading / mid
        var end = itemStart + band.itemWidth - trailing / mid
        if end <= start {   // an item too narrow for its insets: a sliver at its center
            let center = itemStart + band.itemWidth / 2
            start = center - 0.0005
            end = center + 0.0005
        }
        return HighlightGeometry(
            innerRadius: inner, outerRadius: outer, startAngle: start, endAngle: end,
            cornerRadius: cornerRadius(thickness: outer - inner, arcLength: (end - start) * mid, preferred: highlightCornerRadius)
        )
    }

    // MARK: Labels

    /// How wide upright text can be inside a cell that is `thickness` thick (radially) and `tangential` long, whose center
    /// lies at `angle` from 12 o'clock: the horizontal chord through the middle of the rotated cell, minus padding on
    /// both sides. Straight up the room is the tangential length; at 3 or 9 o'clock it is the thickness.
    public func availableTextWidth(thickness: Double, tangential: Double, angle: Double, padding: Double) -> Double {
        let s = abs(sin(angle)), c = abs(cos(angle))
        let byThickness = s > 1e-9 ? thickness / s : Double.infinity
        let byLength = c > 1e-9 ? tangential / c : Double.infinity
        let room = min(byThickness, byLength)
        return max(0, (room.isFinite ? room : 0) - 2 * padding)
    }

    /// The font size at which a label measuring `textWidthAtBaseSize` at the base size fits `available`: the base size if
    /// it already fits, scaled down if not, never below the minimum (what still does not fit is truncated).
    public func fittedFontSize(textWidthAtBaseSize width: Double, available: Double) -> Double {
        guard width.isFinite, width > 0 else { return labelBaseSize }
        guard available > 0 else { return labelMinSize }
        let scale = available / width
        return scale >= 1 ? labelBaseSize : max(labelMinSize, labelBaseSize * scale)
    }
}
