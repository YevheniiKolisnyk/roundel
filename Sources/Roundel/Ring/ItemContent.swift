import RoundelCore
import SwiftUI

/// An item's icon or label, its "opens an arc" chevron and its on-state dot, placed on the item's axis. Content stays
/// inside the cell's safe box (`RingStyle.cellRoom`), which for a group also keeps clear of the chevron's slot.
struct ItemContent: View {
    let display: DisplayItem
    let band: RingBand
    let index: Int
    let emphasis: RingEmphasis
    let side: Double

    private let style = RingStyle.standard
    private let info = SurfaceInfo()
    private let design = DesignMetrics.standard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let traits = style.traits(for: emphasis, increaseContrast: info.increaseContrast, isDark: scheme == .dark)
        let angle = band.centerAngle(ofItem: index)
        let middle = CGPoint(x: side / 2, y: side / 2)
        let iconPoint = WedgeShape.point(center: middle, radius: band.iconRadius, angle: angle)
        let tint: Color = emphasis == .hovered ? .white : .primary
        let hasChevron = display.item.isGroup
        let size = ContentFit.iconSize(band: band, index: index, hasChevron: hasChevron, scale: style.hoverIconScale, style: style)
        let fade = design.resolve(design.ringHighlightMotion, reduceMotion: info.reduceMotion).animation

        ZStack {
            IconView(icon: display.icon, size: size, tint: tint, band: band, index: index, hasChevron: hasChevron)
                .scaleEffect(traits.iconScale)
                .opacity(traits.iconOpacity)
                .animation(fade, value: emphasis)
                .position(iconPoint)

            if display.item.isActive == true {
                // A toggle that is currently on (caffeinate, dark mode, mute): a small dot at the icon's corner.
                Circle()
                    .fill(Color.green)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .position(x: iconPoint.x + size * 0.5, y: iconPoint.y - size * 0.5)
                    .opacity(traits.iconOpacity)
            }

            if hasChevron {
                // A fixed slot just inside the outer rim; content is kept out of it by `cellRoom`.
                Image(systemName: "chevron.up")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .foregroundStyle(tint.opacity(emphasis == .hovered ? 0.85 : style.chevronOpacity))
                    .rotationEffect(.radians(angle))
                    .position(WedgeShape.point(center: middle, radius: band.outerRadius - style.chevronInset, angle: angle))
                    .opacity(traits.iconOpacity)
                    .animation(fade, value: emphasis)
            }
        }
        .frame(width: side, height: side)
    }
}

/// One icon: SF Symbols in one weight and hierarchical rendering, emoji and pictures in the same square, short words
/// (format names) fitted to their cell and truncated if they still do not fit.
private struct IconView: View {
    let icon: ResolvedIcon
    /// The fitted size of the icon's square.
    let size: Double
    let tint: Color
    let band: RingBand
    let index: Int
    let hasChevron: Bool

    private let style = RingStyle.standard

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.95, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        case .emoji(let value):
            Text(value).font(.system(size: size * 0.85))
        case .image(let image):
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
        case .letter(let letter):
            letterView(letter)
        }
    }

    @ViewBuilder
    private func letterView(_ letter: String) -> some View {
        if letter.count <= 1 {
            Text(letter)
                .font(.system(size: size * 0.95, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        } else if let fit = ContentFit.label(letter, band: band, index: index, hasChevron: hasChevron, scale: style.hoverIconScale, style: style) {
            Text(letter)
                .font(.system(size: fit.fontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(tint)
                .frame(width: fit.maxWidth)
        }
    }
}
