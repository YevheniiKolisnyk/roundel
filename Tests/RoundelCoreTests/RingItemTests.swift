import XCTest
@testable import RoundelCore

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
