import AppKit
import RoundelCore

/// How big an item's content may be drawn in its cell: the pure rules of `RingStyle` fed with real text measurements.
enum ContentFit {
    /// A little extra on measured text widths: kerning and rounding make text at another size not exactly proportional.
    private static let widthSafety = 1.03

    /// Size of `text` in the label font at `size`.
    static func measure(_ text: String, size: Double) -> (width: Double, height: Double) {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        let height = NSLayoutManager().defaultLineHeight(for: font)
        return (Double(width), Double(height))
    }

    /// The font size and widest extent for a short text in item `index` of `band` (nil: nothing fits, draw nothing).
    static func label(_ text: String, band: RingBand, index: Int, hasChevron: Bool, scale: Double, style: RingStyle) -> RingStyle.LabelFit? {
        let base = measure(text, size: style.labelBaseSize)
        return style.labelFit(widthAtBaseSize: base.width * widthSafety, heightAtBaseSize: base.height,
                              angle: band.centerAngle(ofItem: index), in: style.cellRoom(for: band, hasChevron: hasChevron), scale: scale)
    }

    /// The size of a square icon (symbol, emoji, picture, one letter): the band's size, or less if the cell is too small.
    static func iconSize(band: RingBand, index: Int, hasChevron: Bool, scale: Double, style: RingStyle) -> Double {
        let k = style.fitScale(width: band.iconSize, height: band.iconSize, angle: band.centerAngle(ofItem: index),
                               in: style.cellRoom(for: band, hasChevron: hasChevron), scale: scale)
        return band.iconSize * min(1, k)
    }
}
