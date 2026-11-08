import AppKit
import RoundelCore

/// How big an item's content may be drawn in its cell: the pure rules of `RingStyle` fed with real text measurements.
enum ContentFit {
    /// A little extra on measured text widths: kerning and rounding make text at another size not exactly proportional.
    private static let widthSafety = 1.03
    /// Line heights are rounded per size, so they are not exactly proportional either.
    private static let heightSafety = 1.06

    /// Size of `text` in the label font (rounded, semibold, like the icons' words) or in the plain system font.
    static func measure(_ text: String, size: Double, rounded: Bool = true, weight: NSFont.Weight = .semibold) -> (width: Double, height: Double) {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = rounded ? (base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base) : base
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        let height = NSLayoutManager().defaultLineHeight(for: font)
        return (Double(width), Double(height))
    }

    /// The font size and widest extent for a short text in item `index` of `band` (nil: nothing fits, draw nothing).
    static func label(_ text: String, band: RingBand, index: Int, hasChevron: Bool, scale: Double, style: RingStyle) -> RingStyle.LabelFit? {
        let base = measure(text, size: style.labelBaseSize)
        return style.labelFit(widthAtBaseSize: base.width * widthSafety, heightAtBaseSize: base.height * heightSafety,
                              angle: band.centerAngle(ofItem: index), in: style.cellRoom(for: band, hasChevron: hasChevron), scale: scale)
    }

    /// The size of a square icon (symbol, emoji, picture, one letter): the band's size, or less if the cell is too small.
    static func iconSize(band: RingBand, index: Int, hasChevron: Bool, scale: Double, style: RingStyle) -> Double {
        let k = style.fitScale(width: band.iconSize, height: band.iconSize, angle: band.centerAngle(ofItem: index),
                               in: style.cellRoom(for: band, hasChevron: hasChevron), scale: scale)
        return band.iconSize * min(1, k)
    }

    /// The font size and widest extent for the hovered item's name in the middle (nil: draw nothing).
    static func centerLabel(_ text: String, radius: Double, style: RingStyle) -> RingStyle.LabelFit? {
        let base = measure(text, size: style.centerLabelBaseSize, rounded: false, weight: .medium)
        return style.centerLabelFit(widthAtBaseSize: base.width * widthSafety, heightAtBaseSize: base.height * heightSafety, radius: radius)
    }
}
