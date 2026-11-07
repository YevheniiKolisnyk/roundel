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
        XCTAssertEqual(config.settings.expandDelayMs, 120)
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
            settings: ConfigSettings(openMode: .clickRequired, expandDelayMs: 300),
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

    func testExpandDelayIsClampedToZeroThroughOneThousand() throws {
        XCTAssertEqual(try decode(#"{"version":1,"settings":{"expandDelayMs":-5},"ring":[\#(minimalAction)]}"#).settings.expandDelayMs, 0)
        XCTAssertEqual(try decode(#"{"version":1,"settings":{"expandDelayMs":0},"ring":[\#(minimalAction)]}"#).settings.expandDelayMs, 0, "zero means instantly")
        XCTAssertEqual(try decode(#"{"version":1,"settings":{"expandDelayMs":400},"ring":[\#(minimalAction)]}"#).settings.expandDelayMs, 400)
        XCTAssertEqual(try decode(#"{"version":1,"settings":{"expandDelayMs":1000},"ring":[\#(minimalAction)]}"#).settings.expandDelayMs, 1000)
        XCTAssertEqual(try decode(#"{"version":1,"settings":{"expandDelayMs":5000},"ring":[\#(minimalAction)]}"#).settings.expandDelayMs, 1000)
    }

    func testExpandDelaySecondsAccessor() {
        XCTAssertEqual(ConfigSettings(expandDelayMs: 400).expandDelay, 0.4, accuracy: 1e-9)
        XCTAssertEqual(ConfigSettings(expandDelayMs: 0).expandDelay, 0)
    }

    func testSettingsInitClamps() {
        XCTAssertEqual(ConfigSettings(expandDelayMs: -1).expandDelayMs, 0)
        XCTAssertEqual(ConfigSettings(expandDelayMs: 99_999).expandDelayMs, 1000)
    }

    func testOldDwellSettingsStillLoadAndAreIgnored() throws {
        let config = try decode(#"{"version":1,"settings":{"openMode":"clickRequired","dwellMs":600,"centerDwellMs":900},"ring":[\#(minimalAction)]}"#)
        XCTAssertEqual(config.settings.openMode, .clickRequired)
        XCTAssertEqual(config.settings.expandDelayMs, 120, "dwellMs does not leak into expandDelayMs")
    }

    func testOldDwellSettingsAreNotWrittenBack() throws {
        let data = try ConfigLoader.encode(RoundelConfig(ring: [.action(ActionNode(id: "a", title: "A", action: "x"))]))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("expandDelayMs"))
        XCTAssertFalse(text.contains("dwellMs"))
        XCTAssertFalse(text.contains("centerDwellMs"))
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
