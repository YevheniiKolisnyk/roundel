import XCTest
@testable import RoundelCore

final class RingMetricsTests: XCTestCase {
    func testSmallRingsUseTheMinimumSize() {
        for count in 1...12 {
            XCTAssertEqual(RingMetrics.make(sectionCount: count).outerRadius, RingMetrics.minOuterRadius, "N=\(count)")
        }
    }

    func testRadiusGrowsMonotonicallyWithSectionCount() {
        var previous = 0.0
        for count in 1...40 {
            let radius = RingMetrics.make(sectionCount: count).outerRadius
            XCTAssertGreaterThanOrEqual(radius, previous, "N=\(count)")
            previous = radius
        }
        XCTAssertGreaterThan(RingMetrics.make(sectionCount: 20).outerRadius, RingMetrics.minOuterRadius)
    }

    func testRadiusIsCapped() {
        for count in [30, 100, 1_000] {
            XCTAssertEqual(RingMetrics.make(sectionCount: count).outerRadius, RingMetrics.defaultMaxOuterRadius, "N=\(count)")
        }
        XCTAssertEqual(RingMetrics.make(sectionCount: 100, maxOuterRadius: 150).outerRadius, 150)
    }

    func testCapNeverDropsBelowTheMinimum() {
        XCTAssertEqual(RingMetrics.make(sectionCount: 100, maxOuterRadius: 50).outerRadius, RingMetrics.minOuterRadius)
    }

    func testCrowdingThreshold() {
        XCTAssertFalse(RingMetrics.make(sectionCount: 12).isCrowded)
        XCTAssertFalse(RingMetrics.make(sectionCount: 20).isCrowded)
        XCTAssertTrue(RingMetrics.make(sectionCount: 25).isCrowded)
        XCTAssertTrue(RingMetrics.make(sectionCount: 200).isCrowded)
    }

    func testPanelSideIsEvenAndContainsTheRing() {
        for count in [1, 6, 13, 18, 50] {
            let metrics = RingMetrics.make(sectionCount: count)
            XCTAssertEqual(metrics.panelSide.truncatingRemainder(dividingBy: 2), 0, "N=\(count)")
            XCTAssertGreaterThanOrEqual(metrics.panelSide, 2 * metrics.outerRadius)
        }
    }

    func testIconSizeShrinksWhenCrowdedButStaysReadable() {
        XCTAssertEqual(RingMetrics.make(sectionCount: 6).iconSize, 24)
        let crowded = RingMetrics.make(sectionCount: 500).iconSize
        XCTAssertGreaterThanOrEqual(crowded, 10)
        XCTAssertLessThan(crowded, 24)
    }

    func testIconRadiusSitsInsideTheRing() {
        for count in [1, 6, 30, 500] {
            let metrics = RingMetrics.make(sectionCount: count)
            XCTAssertGreaterThan(metrics.iconRadius, metrics.deadZoneRadius)
            XCTAssertLessThan(metrics.iconRadius, metrics.outerRadius)
        }
    }

    func testGeometryReachesEverySectionForAnyCount() {
        for count in [1, 2, 3, 17, 100, 500] {
            let geometry = RingMetrics.make(sectionCount: count).geometry
            XCTAssertEqual(geometry.sectionCount, count)
            for index in stride(from: 0, to: count, by: max(1, count / 25)) {
                let angle = geometry.centerAngle(ofSection: index)
                let dx = 100 * sin(angle), dy = 100 * cos(angle)
                XCTAssertEqual(geometry.sectionIndex(dx: dx, dy: dy), index, "N=\(count) section \(index)")
            }
        }
    }

    func testZeroSectionsDoesNotCrash() {
        XCTAssertEqual(RingMetrics.make(sectionCount: 0).geometry.sectionCount, 1)
    }

    // MARK: Crowded levels across a whole config

    func testCrowdedLevelsListsEveryOverfullRing() {
        func actions(_ prefix: String, _ n: Int) -> [Node] {
            (0..<n).map { .action(ActionNode(id: "\(prefix)\($0)", title: "t", action: "x")) }
        }
        let config = RoundelConfig(version: 1, settings: ConfigSettings(), ring: [
            .group(GroupNode(id: "small", title: "s", children: actions("s", 5))),
            .group(GroupNode(id: "big", title: "b", children: actions("b", 40) + [
                .group(GroupNode(id: "inner", title: "i", children: actions("i", 30))),
            ])),
        ] + actions("r", 3))

        let crowded = RingMetrics.crowdedLevels(in: config)
        XCTAssertEqual(crowded.map(\.path), [["big"], ["big", "inner"]])
        XCTAssertEqual(crowded.map(\.count), [41, 30])
    }

    func testNoCrowdedLevelsForNormalConfig() {
        XCTAssertTrue(RingMetrics.crowdedLevels(in: DefaultConfig.config).isEmpty)
    }
}

final class RingItemTests: XCTestCase {
    func testItemsReflectNodes() {
        let nodes: [Node] = [
            .action(ActionNode(id: "a", title: "A", icon: .symbol("star"), action: "known")),
            .group(GroupNode(id: "g", title: "G", icon: .emoji("🚀"), children: [.action(ActionNode(id: "c", title: "C", action: "x"))])),
        ]
        let items = RingItem.items(for: nodes)
        XCTAssertEqual(items.map(\.id), ["a", "g"])
        XCTAssertEqual(items.map(\.isGroup), [false, true])
        XCTAssertEqual(items.map(\.isDimmed), [false, false])
        XCTAssertEqual(items[0].icon, .symbol("star"))
        XCTAssertEqual(items[1].title, "G")
    }

    func testUnavailableActionsAreDimmedButGroupsNever() {
        // M3 hook: an unknown action id is a runtime warning (dimmed node), never a config error.
        let nodes: [Node] = [
            .action(ActionNode(id: "ok", title: "OK", action: "known")),
            .action(ActionNode(id: "bad", title: "Bad", action: "unknown.id")),
            .group(GroupNode(id: "g", title: "G", children: [.action(ActionNode(id: "c", title: "C", action: "x"))])),
        ]
        let items = RingItem.items(for: nodes, isAvailable: { $0.action == "known" })
        XCTAssertEqual(items.map(\.isDimmed), [false, true, false])
    }

    func testFallbackLetterUsesFirstCharacterOfTitle() {
        XCTAssertEqual(RingItem.fallbackLetter(for: "terminal"), "T")
        XCTAssertEqual(RingItem.fallbackLetter(for: "  ёлка"), "Ё")
        XCTAssertEqual(RingItem.fallbackLetter(for: "🚀 Rocket"), "🚀")
        XCTAssertEqual(RingItem.fallbackLetter(for: ""), "•")
    }
}
