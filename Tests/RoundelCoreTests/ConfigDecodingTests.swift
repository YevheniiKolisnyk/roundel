import XCTest
@testable import RoundelCore

final class ConfigDecodingTests: XCTestCase {
    private func parse(_ json: String) -> Result<RoundelConfig, ConfigLoadFailure> {
        ConfigLoader.parse(Data(json.utf8))
    }

    private func decode(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> RoundelConfig {
        switch parse(json) {
        case .success(let config): return config
        case .failure(let failure):
            XCTFail("expected success, got: \(failure.description)", file: file, line: line)
            throw failure
        }
    }

    private func failure(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> ConfigLoadFailure? {
        if case .failure(let failure) = parse(json) { return failure }
        XCTFail("expected failure", file: file, line: line)
        return nil
    }

    private func wrap(_ node: String) -> String { #"{"version":1,"ring":[\#(node)]}"# }

    private let minimalAction = #"{"type":"action","id":"a","title":"A","action":"log"}"#

    // MARK: Defaults

    func testMinimalConfigDecodesWithDefaults() throws {
        let config = try decode(wrap(minimalAction))
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.settings.openMode, .holdRelease)
        XCTAssertEqual(config.settings.dwellMs, 250)
        XCTAssertEqual(config.settings.centerDwellMs, 250)
        XCTAssertEqual(config.ring.count, 1)
        guard case .action(let action) = config.ring[0] else { return XCTFail("expected action") }
        XCTAssertEqual(action.id, "a")
        XCTAssertEqual(action.action, "log")
        XCTAssertEqual(action.params, .object([:]))
        XCTAssertNil(action.icon)
    }

    // MARK: Round trip

    func testEncodeDecodeRoundTrip() throws {
        let config = RoundelConfig(
            version: 1,
            settings: ConfigSettings(openMode: .clickRequired, dwellMs: 300, centerDwellMs: 400),
            ring: [
                .action(ActionNode(id: "a", title: "A", icon: .symbol("star"), action: "log",
                                   params: .object(["n": .number(1.5), "list": .array([.string("x"), .null, .bool(true)])]))),
                .group(GroupNode(id: "g", title: "G", icon: .emoji("🚀"), children: [
                    .action(ActionNode(id: "c", title: "C", icon: .image("icons/c.png"), action: "log")),
                    .group(GroupNode(id: "g2", title: "G2", icon: nil, children: [
                        .action(ActionNode(id: "d", title: "D", action: "whatever")),
                    ])),
                ])),
            ]
        )
        let data = try ConfigLoader.encode(config)
        XCTAssertEqual(try ConfigLoader.parse(data).get(), config)
    }

    func testGroupsNestToAnyDepth() throws {
        var json = #"{"type":"action","id":"leaf","title":"Leaf","action":"log"}"#
        for level in stride(from: 40, through: 1, by: -1) {
            json = #"{"type":"group","id":"g\#(level)","title":"G","children":[\#(json)]}"#
        }
        let config = try decode(wrap(json))
        var node = config.ring[0]
        var depth = 0
        while case .group(let group) = node { node = group.children[0]; depth += 1 }
        XCTAssertEqual(depth, 40)
        XCTAssertEqual(node.id, "leaf")
    }

    func testParamsKeepArbitraryJSON() throws {
        let config = try decode(wrap(#"{"type":"action","id":"a","title":"A","action":"x","params":{"a":[1,{"b":null}],"c":"d","e":false}}"#))
        guard case .action(let action) = config.ring[0] else { return XCTFail() }
        XCTAssertEqual(action.params, .object([
            "a": .array([.number(1), .object(["b": .null])]),
            "c": .string("d"),
            "e": .bool(false),
        ]))
    }

    // MARK: Unknown fields

    func testUnknownFieldsAreIgnoredEverywhere() throws {
        let json = #"""
        {"version":1,"_comment":"top","future":{"x":1},
         "settings":{"openMode":"clickRequired","_comment":"s","somethingNew":true},
         "ring":[{"type":"action","id":"a","title":"A","action":"log","_comment":"n","extra":[1],
                  "icon":{"symbol":"star","_comment":"i"}}]}
        """#
        let config = try decode(json)
        XCTAssertEqual(config.settings.openMode, .clickRequired)
        XCTAssertEqual(config.ring[0].icon, .symbol("star"))
    }

    // MARK: Icons

    func testThreeIconKinds() throws {
        let config = try decode(#"""
        {"version":1,"ring":[
          {"type":"action","id":"a","title":"A","action":"x","icon":{"symbol":"star.fill"}},
          {"type":"action","id":"b","title":"B","action":"x","icon":{"emoji":"🚀"}},
          {"type":"action","id":"c","title":"C","action":"x","icon":{"image":"icons/c.png"}}]}
        """#)
        XCTAssertEqual(config.ring.map(\.icon), [.symbol("star.fill"), .emoji("🚀"), .image("icons/c.png")])
    }

    func testIconNeedsExactlyOneKey() {
        let none = failure(wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{}}"#))
        XCTAssertEqual(none?.issues.first?.path, "ring[0].icon")
        let two = failure(wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{"symbol":"a","emoji":"🚀"}}"#))
        XCTAssertEqual(two?.issues.first?.path, "ring[0].icon")
    }

    func testEmojiMustBeOneGrapheme() {
        for bad in ["ab", "🚀🚀", "a", "1", ""] {
            XCTAssertNotNil(failure(wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{"emoji":"\#(bad)"}}"#)), "'\(bad)'")
        }
        for good in ["🚀", "🇺🇦", "❤️", "👨‍👩‍👧"] {
            XCTAssertNoThrow(try decode(wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{"emoji":"\#(good)"}}"#)), good)
        }
    }

    func testImagePathMustStayInsideConfigFolder() {
        for bad in ["/etc/x.png", "../x.png", "a/../../x.png", "~/x.png", "", "a\\b.png"] {
            let json = wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{"image":"\#(bad.replacingOccurrences(of: "\\", with: "\\\\"))"}}"#)
            XCTAssertNotNil(failure(json), "'\(bad)'")
        }
        XCTAssertNoThrow(try decode(wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{"image":"icons/a.png"}}"#)))
        XCTAssertNoThrow(try decode(wrap(#"{"type":"action","id":"a","title":"A","action":"x","icon":{"image":"a/../b.png"}}"#)),
                         "'..' that stays inside the folder is fine")
    }

    // MARK: Structure errors carry a path

    func testUnknownNodeType() {
        let f = failure(wrap(#"{"type":"banana","id":"a","title":"A"}"#))
        XCTAssertEqual(f?.issues.first?.path, "ring[0].type")
    }

    func testMissingActionField() {
        let f = failure(wrap(#"{"type":"action","id":"a","title":"A"}"#))
        XCTAssertEqual(f?.issues.first?.path, "ring[0].action")
    }

    func testMissingChildrenOnGroup() {
        let f = failure(wrap(#"{"type":"group","id":"g","title":"G"}"#))
        XCTAssertEqual(f?.issues.first?.path, "ring[0].children")
    }

    func testErrorPathInsideNestedGroup() {
        let json = wrap(#"{"type":"group","id":"g","title":"G","children":[{"type":"action","id":"a","title":"A","action":"x"},{"type":"group","id":"h","title":"H","children":[{"type":"action","id":"b","title":"B","action":"x","icon":{"emoji":"zz"}}]}]}"#)
        XCTAssertEqual(failure(json)?.issues.first?.path, "ring[0].children[1].children[0].icon")
    }

    func testInvalidOpenMode() {
        let f = failure(#"{"version":1,"settings":{"openMode":"sideways"},"ring":[\#(minimalAction)]}"#)
        XCTAssertEqual(f?.issues.first?.path, "settings.openMode")
    }

    // MARK: Settings

    func testDwellValuesAreClamped() throws {
        let low = try decode(#"{"version":1,"settings":{"dwellMs":10,"centerDwellMs":-5},"ring":[\#(minimalAction)]}"#)
        XCTAssertEqual(low.settings.dwellMs, 100)
        XCTAssertEqual(low.settings.centerDwellMs, 100)
        let high = try decode(#"{"version":1,"settings":{"dwellMs":5000,"centerDwellMs":1001},"ring":[\#(minimalAction)]}"#)
        XCTAssertEqual(high.settings.dwellMs, 1000)
        XCTAssertEqual(high.settings.centerDwellMs, 1000)
        let ok = try decode(#"{"version":1,"settings":{"dwellMs":400,"centerDwellMs":100},"ring":[\#(minimalAction)]}"#)
        XCTAssertEqual(ok.settings.dwellMs, 400)
        XCTAssertEqual(ok.settings.centerDwellMs, 100)
    }

    func testDwellSecondsAccessors() {
        let settings = ConfigSettings(dwellMs: 400, centerDwellMs: 150)
        XCTAssertEqual(settings.dwell, 0.4, accuracy: 1e-9)
        XCTAssertEqual(settings.centerDwell, 0.15, accuracy: 1e-9)
    }

    func testSettingsInitClamps() {
        XCTAssertEqual(ConfigSettings(dwellMs: 1, centerDwellMs: 99999).dwellMs, 100)
        XCTAssertEqual(ConfigSettings(dwellMs: 1, centerDwellMs: 99999).centerDwellMs, 1000)
    }

    // MARK: Lookup

    func testNodeLookupAndPathNavigation() throws {
        let config = try decode(wrap(#"{"type":"group","id":"g","title":"G","children":[{"type":"group","id":"h","title":"H","children":[{"type":"action","id":"a","title":"A","action":"x"}]}]}"#))
        XCTAssertEqual(config.node(withID: "a")?.title, "A")
        XCTAssertNil(config.node(withID: "nope"))
        XCTAssertEqual(config.nodes(at: ["g", "h"])?.map(\.id), ["a"])
        XCTAssertEqual(config.nodes(at: [])?.map(\.id), ["g"])
        XCTAssertNil(config.nodes(at: ["g", "zzz"]))
        XCTAssertNil(config.nodes(at: ["g", "h", "a"]), "an action is not a ring level")
    }
}
