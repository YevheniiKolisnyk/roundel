import AppKit
import RoundelCore
import SwiftUI

/// An item's icon, its "opens an arc" chevron and its on-state dot, placed on the item's axis.
struct ItemContent: View {
    let display: DisplayItem
    let band: RingBand
    let index: Int
    let emphasis: RingEmphasis
    let side: Double

    private let style = RingStyle.standard
    private let info = SurfaceInfo()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let traits = style.traits(for: emphasis, increaseContrast: info.increaseContrast, isDark: scheme == .dark)
        let angle = band.centerAngle(ofItem: index)
        let middle = CGPoint(x: side / 2, y: side / 2)
        let iconPoint = WedgeShape.point(center: middle, radius: band.iconRadius, angle: angle)
        let tint: Color = emphasis == .hovered ? .white : .primary

        ZStack {
            IconView(icon: display.icon, size: band.iconSize, tint: tint, band: band, angle: angle, info: info)
                .scaleEffect(traits.iconScale)
                .opacity(traits.iconOpacity)
                .position(iconPoint)

            if display.item.isActive == true {
                // A toggle that is currently on (caffeinate, dark mode, mute).
                Circle()
                    .fill(Color.green)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .position(x: iconPoint.x + band.iconSize * 0.62, y: iconPoint.y - band.iconSize * 0.62)
                    .opacity(traits.iconOpacity)
            }

            if display.item.isGroup {
                Image(systemName: "chevron.up")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .foregroundStyle(tint.opacity(emphasis == .hovered ? 0.85 : style.chevronOpacity))
                    .rotationEffect(.radians(angle))
                    .position(WedgeShape.point(center: middle, radius: band.outerRadius - style.chevronInset, angle: angle))
                    .opacity(traits.iconOpacity)
            }
        }
        .frame(width: side, height: side)
    }
}

/// One icon: SF Symbols in one weight and hierarchical rendering, emoji and pictures at a balanced size, short words
/// (format names) scaled down to fit their cell.
private struct IconView: View {
    let icon: ResolvedIcon
    let size: Double
    let tint: Color
    let band: RingBand
    let angle: Double
    let info: SurfaceInfo

    private let style = RingStyle.standard

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        case .emoji(let value):
            Text(value).font(.system(size: size * 0.95))
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.1, height: size * 1.1)
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
        } else {
            let available = style.availableTextWidth(thickness: band.outerRadius - band.innerRadius,
                                                     tangential: band.itemWidth * band.iconRadius,
                                                     angle: angle, padding: style.labelPadding)
            let fitted = style.fittedFontSize(textWidthAtBaseSize: Self.width(of: letter, size: style.labelBaseSize), available: available)
            Text(letter)
                .font(.system(size: fitted, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(tint)
                .frame(maxWidth: max(available, 1))
        }
    }

    /// The width of `text` in the label font at `size`.
    static func width(of text: String, size: Double) -> Double {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        return Double((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
