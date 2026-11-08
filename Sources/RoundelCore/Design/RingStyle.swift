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

    // The name of the hovered item, in the middle
    public var centerLabelBaseSize = 11.0
    /// Clear space between the name and the edge of the middle.
    public var centerLabelPadding = 4.0

    // Content (labels, icons) must fit its cell
    public var labelBaseSize = 12.0
    public var labelMinSize = 9.0
    /// Clear space between content and the highlight's edge (or the chevron).
    public var labelPadding = 4.0
    /// How far content stays from every side of its cell: the highlight's own inset plus the padding.
    public var contentInset: Double { highlightInset + labelPadding }
    /// How far from the band's outer rim a group cell's content must stay, so it never meets the chevron.
    public var chevronClearance: Double { chevronInset + chevronSize / 2 + labelPadding }

    // Appearing
    public var appearScale = 0.96
    public var arcAppearScale = 0.96

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

    // MARK: Content must stay inside its cell

    /// Half extents of the box content may occupy, centered on the item's icon point and aligned with the cell: how far
    /// it may reach radially (either way) and tangentially.
    public struct CellRoom: Equatable, Sendable {
        public var halfRadial: Double
        public var halfTangential: Double
        public init(halfRadial: Double, halfTangential: Double) {
            self.halfRadial = halfRadial
            self.halfTangential = halfTangential
        }
    }

    /// The safe box of an item of `band`: `contentInset` from every side of the cell, and, for a group, also clear of
    /// the chevron's slot near the outer rim (so content and chevron cannot collide at any angle).
    public func cellRoom(for band: RingBand, hasChevron: Bool) -> CellRoom {
        let inward = band.iconRadius - (band.innerRadius + contentInset)
        let outward = band.outerRadius - (hasChevron ? chevronClearance : contentInset) - band.iconRadius
        let chordHalf = band.iconRadius * sin(min(band.itemWidth / 2, .pi / 2))
        return CellRoom(halfRadial: max(0, min(inward, outward)), halfTangential: max(0, chordHalf - contentInset))
    }

    /// Whether an upright box of `width` x `height`, centered on the icon point of a cell whose center lies at `angle`
    /// from 12 o'clock, stays inside the cell's safe box. The cell is rotated, the text is not, so the box's corners
    /// matter, not just its sides.
    public func fits(width: Double, height: Double, angle: Double, in room: CellRoom) -> Bool {
        let s = abs(sin(angle)), c = abs(cos(angle))
        let radial = (width * s + height * c) / 2
        let tangential = (width * c + height * s) / 2
        return radial <= room.halfRadial + 1e-9 && tangential <= room.halfTangential + 1e-9
    }

    /// The widest upright box that is `height` tall and still fits; 0 when even a sliver of that height does not.
    public func maxWidth(forHeight height: Double, angle: Double, in room: CellRoom) -> Double {
        guard height.isFinite, height >= 0 else { return 0 }
        let s = abs(sin(angle)), c = abs(cos(angle))
        let radialRoom = room.halfRadial - height / 2 * c
        let tangentialRoom = room.halfTangential - height / 2 * s
        guard radialRoom >= 0, tangentialRoom >= 0 else { return 0 }
        let byRadial = s > 1e-9 ? radialRoom / s : Double.infinity
        let byTangential = c > 1e-9 ? tangentialRoom / c : Double.infinity
        let half = min(byRadial, byTangential)
        return half.isFinite ? 2 * half : 0
    }

    /// The largest factor `k` by which a `width` x `height` box can be scaled (and then drawn at `scale`, e.g. the hover
    /// enlargement) and still fit. Not capped at 1; an empty box needs no shrinking and gives 1.
    public func fitScale(width: Double, height: Double, angle: Double, in room: CellRoom, scale: Double) -> Double {
        let s = abs(sin(angle)), c = abs(cos(angle))
        let radial = (width * s + height * c) / 2 * scale
        let tangential = (width * c + height * s) / 2 * scale
        guard radial > 0 || tangential > 0 else { return 1 }
        let byRadial = radial > 0 ? room.halfRadial / radial : Double.infinity
        let byTangential = tangential > 0 ? room.halfTangential / tangential : Double.infinity
        return max(0, min(byRadial, byTangential))
    }

    /// How to draw a one-line label: the font size and the widest the text may be (longer text is truncated).
    public struct LabelFit: Equatable, Sendable {
        public var fontSize: Double
        public var maxWidth: Double
    }

    /// Fits a label measuring `widthAtBaseSize` x `heightAtBaseSize` at the base font size into `room`, for a cell at
    /// `angle`, drawn at `scale` (hover). Scaled down as far as the minimum size; beyond that it is truncated to what
    /// fits. Nil when there is no room for even a short line (or the measurements are nonsense): draw nothing.
    public func labelFit(widthAtBaseSize width: Double, heightAtBaseSize height: Double, angle: Double, in room: CellRoom, scale: Double) -> LabelFit? {
        guard width.isFinite, width > 0, height.isFinite, height > 0, scale.isFinite, scale > 0 else { return nil }
        let k = fitScale(width: width, height: height, angle: angle, in: room, scale: scale)
        let wanted = labelBaseSize * min(1, k)
        if wanted >= labelMinSize {
            return LabelFit(fontSize: wanted, maxWidth: width * wanted / labelBaseSize)
        }
        let drawnHeight = height * labelMinSize / labelBaseSize * scale
        let room = maxWidth(forHeight: drawnHeight, angle: angle, in: room) / scale
        guard room >= labelMinSize else { return nil }
        return LabelFit(fontSize: labelMinSize, maxWidth: min(room, width * labelMinSize / labelBaseSize))
    }

    // MARK: The label in the middle

    /// Fits a one-line name measuring `widthAtBaseSize` x `heightAtBaseSize` at `centerLabelBaseSize` into the circle of
    /// the middle (`radius`), keeping `centerLabelPadding` from its edge: scaled down as far as the minimum size, then
    /// truncated to what fits. Nil when nothing useful fits (or the measurements are nonsense).
    public func centerLabelFit(widthAtBaseSize width: Double, heightAtBaseSize height: Double, radius: Double) -> LabelFit? {
        guard width.isFinite, width > 0, height.isFinite, height > 0, radius.isFinite else { return nil }
        let usable = radius - centerLabelPadding
        guard usable > 0 else { return nil }
        let k = usable / (hypot(width, height) / 2)
        let wanted = centerLabelBaseSize * min(1, k)
        if wanted >= labelMinSize {
            return LabelFit(fontSize: wanted, maxWidth: width * wanted / centerLabelBaseSize)
        }
        let h = height * labelMinSize / centerLabelBaseSize
        guard h / 2 < usable else { return nil }
        let room = 2 * (usable * usable - (h / 2) * (h / 2)).squareRoot()
        guard room >= labelMinSize else { return nil }
        return LabelFit(fontSize: labelMinSize, maxWidth: min(room, width * labelMinSize / centerLabelBaseSize))
    }
}
