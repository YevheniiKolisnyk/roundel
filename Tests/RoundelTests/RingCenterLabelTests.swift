import XCTest
import SwiftUI
import RoundelCore
@testable import Roundel

/// The hovered item's name in the middle of the ring.
@MainActor
final class RingCenterLabelTests: XCTestCase {
    private let style = RingStyle.standard
    private let hovered = RingItemRef(level: 0, index: 1)

    private func model(title: String, dimmed: Bool = false) -> RingModel {
        let model = RingFixture.model(hover: hovered)
        let old = model.bands[0].items[1]
        let item = RingItem(id: old.item.id, title: title, icon: old.item.icon, isGroup: old.item.isGroup, isDimmed: dimmed)
        var items = model.bands[0].items
        items[1] = DisplayItem(item: item, icon: old.icon)
        model.bands[0] = BandModel(band: model.bands[0].band, items: items, connector: nil)
        return model
    }

    private func render(_ model: RingModel) throws -> Pixels {
        let side = model.panelSide
        return try XCTUnwrap(Pixels(of: RingView(model: model, frozen: .shown).frame(width: side, height: side)
            .environment(\.colorScheme, .dark).environment(\.surfacePreference, .solid), scale: 2))
    }

    func testEveryNameFitsTheCircleOfTheMiddle() {
        let radius = RingMetrics.standard.deadZoneRadius
        for text in ["Aa", "Lock", "Caffeinate", "Dark mode", "Convert image", "Вимкнути екран", "Дуже довга назва пункту меню, яка не поміститься", "A", "WebP"] {
            guard let fit = ContentFit.centerLabel(text, radius: radius, style: style) else { continue }
            let measured = ContentFit.measure(text, size: fit.fontSize, rounded: false, weight: .medium)
            let width = min(measured.width, fit.maxWidth)
            XCTAssertLessThanOrEqual((width / 2) * (width / 2) + (measured.height / 2) * (measured.height / 2),
                                     (radius - style.centerLabelPadding) * (radius - style.centerLabelPadding) + 1e-6, "'\(text)'")
        }
        XCTAssertNotNil(ContentFit.centerLabel("Lock", radius: radius, style: style), "a short name is always shown")
    }

    func testTheNameAppearsOnlyInsideTheMiddleAndNothingElseMoves() throws {
        let without = try render(model(title: ""))
        let with = try render(model(title: "Convert image"))
        let side = with.alpha(atPointX: 0, y: 0) >= 0 ? Double(with.width) / with.scale : 0
        let center = side / 2
        let hole = RingMetrics.standard.deadZoneRadius
        var inHole = 0
        for y in 0..<with.height {
            for x in 0..<with.width {
                let a = with.rgba(x, y), b = without.rgba(x, y)
                let different = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) + abs(a.a - b.a) > 0.02
                guard different else { continue }
                let dx = (Double(x) + 0.5) / with.scale - center, dy = (Double(y) + 0.5) / with.scale - center
                let r = hypot(dx, dy)
                XCTAssertLessThanOrEqual(r, hole + 0.5, "a pixel changed outside the middle at (\(x), \(y))")
                inHole += 1
            }
        }
        XCTAssertGreaterThan(inHole, 50, "the name is drawn")
    }

    func testChangingTheNameChangesOnlyTheMiddle() throws {
        let a = try render(model(title: "Lock screen"))
        let b = try render(model(title: "Caffeinate"))
        let center = Double(a.width) / a.scale / 2
        for y in 0..<a.height {
            for x in 0..<a.width {
                let p = a.rgba(x, y), q = b.rgba(x, y)
                guard abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) + abs(p.a - q.a) > 0.02 else { continue }
                let r = hypot((Double(x) + 0.5) / a.scale - center, (Double(y) + 0.5) / a.scale - center)
                XCTAssertLessThanOrEqual(r, RingMetrics.standard.deadZoneRadius + 0.5)
            }
        }
    }

    func testNoItemUnderThePointerMeansNoName() throws {
        let model = RingFixture.model(hover: nil)
        let rendered = try render(model)
        let center = Double(rendered.width) / rendered.scale / 2
        // Only the thin ring indicator is in the middle: the area just inside the hole's edge, away from it, is empty.
        XCTAssertLessThan(rendered.alpha(atPointX: center + 20, y: center + 8), 0.05)
    }

    func testADisabledItemsNameIsStillShown() throws {
        let enabled = try render(model(title: "Convert image"))
        let disabled = try render(model(title: "Convert image", dimmed: true))
        var changed = 0
        for y in 0..<enabled.height { for x in 0..<enabled.width {
            let p = enabled.rgba(x, y), q = disabled.rgba(x, y)
            if abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) > 0.1 { changed += 1 }
        } }
        XCTAssertGreaterThan(changed, 0, "a different (secondary) look")
    }
}
