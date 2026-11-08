import XCTest
import SwiftUI
import RoundelCore
@testable import Roundel

/// The format arc as drawn: every label's ink, measured in a real render of the hovered cell (real font, rotation,
/// hover scale), is whole and inside the cell's highlight.
@MainActor
final class FormatArcRenderTests: XCTestCase {
    private let style = RingStyle.standard

    private func render(_ model: RingModel) throws -> Pixels {
        let side = model.panelSide
        return try XCTUnwrap(Pixels(of: RingView(model: model, frozen: .shown).frame(width: side, height: side)
            .environment(\.colorScheme, .dark).environment(\.surfacePreference, .solid), scale: 2))
    }

    func testEveryFormatLabelIsFullyVisibleInsideItsCellAsRendered() throws {
        let hoverLevel = 2
        let model = RingFixture.model(path: RingFixture.formatPath)
        let arc = try XCTUnwrap(model.bands.last)
        let side = model.panelSide
        let center = side / 2
        for (index, display) in arc.items.enumerated() {
            guard case .letter(let text) = display.icon else { return XCTFail("format cells carry their name as text") }
            let fit = try XCTUnwrap(ContentFit.label(text, band: arc.band, index: index, hasChevron: false, scale: style.hoverIconScale, style: style))

            // The cell hovered, with its label and without it: the difference is exactly the label's ink.
            let withLabel = RingFixture.model(path: RingFixture.formatPath, hover: RingItemRef(level: hoverLevel, index: index))
            let withoutLabel = RingFixture.model(path: RingFixture.formatPath, hover: RingItemRef(level: hoverLevel, index: index))
            var items = withoutLabel.bands[hoverLevel].items
            items[index] = DisplayItem(item: items[index].item, icon: .letter(""))
            withoutLabel.bands[hoverLevel] = BandModel(band: withoutLabel.bands[hoverLevel].band, items: items, connector: withoutLabel.bands[hoverLevel].connector)
            let a = try render(withLabel), b = try render(withoutLabel)

            let g = style.highlightGeometry(for: arc.band, index: index)
            let safe = RingBandShape(innerRadius: g.innerRadius, outerRadius: g.outerRadius, startAngle: g.startAngle, endAngle: g.endAngle, cornerRadius: g.cornerRadius)
                .inset(by: 3).path(in: CGRect(x: 0, y: 0, width: side, height: side))

            var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
            for y in 0..<a.height { for x in 0..<a.width {
                let p = a.rgba(x, y), q = b.rgba(x, y)
                guard abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) > 0.25 else { continue }
                let point = CGPoint(x: (Double(x) + 0.5) / a.scale, y: (Double(y) + 0.5) / a.scale)
                XCTAssertTrue(safe.contains(point), "'\(text)': ink at \(point) is outside the cell's safe area (center \(center))")
                minX = min(minX, point.x); maxX = max(maxX, point.x); minY = min(minY, point.y); maxY = max(maxY, point.y)
            } }
            // Whole word: the ink spans (nearly) the width the text has at the size it is drawn, enlarged by the hover scale,
            // measured along the text's own horizontal axis. A word cut to "We…" would be far narrower.
            let expected = ContentFit.measure(text, size: fit.fontSize).width * style.hoverIconScale
            XCTAssertGreaterThanOrEqual(maxX - minX, expected * 0.78, "'\(text)' looks cut: ink \(maxX - minX) pt of \(expected) pt")
            XCTAssertGreaterThanOrEqual(fit.fontSize, 11 - 1e-9)
        }
    }
}
