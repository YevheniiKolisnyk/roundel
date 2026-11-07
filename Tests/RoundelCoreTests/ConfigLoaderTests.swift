import XCTest
@testable import RoundelCore

final class ConfigLoaderTests: XCTestCase {
    private let good1 = Data(#"{"version":1,"ring":[{"type":"action","id":"a","title":"A","action":"log"}]}"#.utf8)
    private let good2 = Data(#"{"version":1,"ring":[{"type":"action","id":"b","title":"B","action":"log"},{"type":"action","id":"c","title":"C","action":"log"}]}"#.utf8)

    // MARK: Error locations

    func testSyntaxErrorReportsLineAndColumn() {
        let broken = """
        {
          "version": 1,
          "ring": [
            { "type": "action" "id": "a" }
          ]
        }
        """
        guard case .failure(let failure) = ConfigLoader.parse(Data(broken.utf8)) else { return XCTFail("expected failure") }
        let issue = failure.issues[0]
        XCTAssertEqual(issue.line, 4, issue.description)
        XCTAssertNotNil(issue.column)
        XCTAssertNil(issue.path)
        XCTAssertTrue(issue.description.contains("line 4"), issue.description)
    }

    func testSchemaErrorReportsPathNotLine() {
        let json = #"{"version":1,"ring":[{"type":"action","id":"a","title":"A","action":"x"},{"type":"group","id":"g","title":"G","children":[{"type":"action","id":"b","title":"B","action":"x","icon":{}}]}]}"#
        guard case .failure(let failure) = ConfigLoader.parse(Data(json.utf8)) else { return XCTFail("expected failure") }
        let issue = failure.issues[0]
        XCTAssertEqual(issue.path, "ring[1].children[0].icon")
        XCTAssertNil(issue.line)
        XCTAssertTrue(issue.description.hasPrefix("ring[1].children[0].icon"), issue.description)
    }

    func testEmptyFileIsAClearError() {
        guard case .failure(let failure) = ConfigLoader.parse(Data()) else { return XCTFail("expected failure") }
        XCTAssertTrue(failure.description.lowercased().contains("empty"), failure.description)
    }

    func testTopLevelMustBeAnObject() {
        guard case .failure = ConfigLoader.parse(Data("[1,2]".utf8)) else { return XCTFail("expected failure") }
    }

    // MARK: Reading files

    func testLoadFromFileAndMissingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("config.json")
        try good1.write(to: file)
        XCTAssertEqual(try ConfigLoader.load(from: file).get().ring.count, 1)

        guard case .failure(let failure) = ConfigLoader.load(from: dir.appendingPathComponent("nope.json")) else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(failure.description.contains("nope.json"), failure.description)
    }

    // MARK: Keep the last good config

    func testRejectedConfigKeepsLastGood() throws {
        var state = ConfigState(initial: try ConfigLoader.parse(good1).get())
        guard case .rejected(let failure) = state.apply(Data("{".utf8)) else { return XCTFail("expected rejection") }
        XCTAssertEqual(state.config.ring.map(\.id), ["a"])
        XCTAssertEqual(state.lastFailure, failure)
    }

    func testUpdateReplacesConfig() throws {
        var state = ConfigState(initial: try ConfigLoader.parse(good1).get())
        XCTAssertEqual(state.apply(good2), .updated)
        XCTAssertEqual(state.config.ring.map(\.id), ["b", "c"])
        XCTAssertNil(state.lastFailure)
    }

    func testIdenticalDataIsUnchanged() throws {
        var state = ConfigState(initial: try ConfigLoader.parse(good1).get())
        XCTAssertEqual(state.apply(good1), .unchanged)
        XCTAssertEqual(state.apply(good2), .updated)
        XCTAssertEqual(state.apply(good2), .unchanged)
    }

    func testSameBadDataIsNotReportedTwice() throws {
        var state = ConfigState(initial: try ConfigLoader.parse(good1).get())
        let bad = Data("{".utf8)
        guard case .rejected = state.apply(bad) else { return XCTFail() }
        XCTAssertEqual(state.apply(bad), .unchanged, "no repeated toasts for the same broken file")
        guard case .rejected = state.apply(Data("{{".utf8)) else { return XCTFail("different bad data is reported") }
    }

    func testRecoveryClearsFailure() throws {
        var state = ConfigState(initial: try ConfigLoader.parse(good1).get())
        _ = state.apply(Data("{".utf8))
        XCTAssertNotNil(state.lastFailure)
        XCTAssertEqual(state.apply(good1), .recovered, "fixed back to what is already loaded")
        XCTAssertNil(state.lastFailure)

        _ = state.apply(Data("{".utf8))
        XCTAssertEqual(state.apply(good2), .updated)
        XCTAssertNil(state.lastFailure)
    }

    func testNewerVersionKeepsLastGood() throws {
        var state = ConfigState(initial: try ConfigLoader.parse(good1).get())
        let v2 = Data(#"{"version":2,"ring":[]}"#.utf8)
        guard case .rejected(let failure) = state.apply(v2) else { return XCTFail() }
        XCTAssertTrue(failure.description.contains("newer"))
        XCTAssertEqual(state.config.ring.map(\.id), ["a"])
    }

    // MARK: Default config

    func testDefaultConfigIsValidAndRich() throws {
        let config = try ConfigLoader.parse(Data(DefaultConfig.json.utf8)).get()
        XCTAssertEqual(config, DefaultConfig.config)
        XCTAssertGreaterThanOrEqual(config.ring.count, 4)

        let groups = config.ring.compactMap { node -> GroupNode? in if case .group(let g) = node { return g }; return nil }
        XCTAssertGreaterThanOrEqual(groups.count, 1)
        XCTAssertGreaterThanOrEqual(groups[0].children.count, 2)
        XCTAssertTrue(groups[0].children.contains(where: \.isGroup), "default config shows a nested group")

        let icons = config.ring.compactMap(\.icon)
        XCTAssertTrue(icons.contains { if case .symbol = $0 { return true }; return false })
        XCTAssertTrue(icons.contains { if case .emoji = $0 { return true }; return false })
    }

    func testDefaultConfigIsDocumented() {
        XCTAssertTrue(DefaultConfig.json.contains("_comment"))
    }

    func testWriteIfMissingCreatesButNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")

        XCTAssertTrue(try DefaultConfig.writeIfMissing(at: file), "creates folder and file")
        XCTAssertEqual(try Data(contentsOf: file), Data(DefaultConfig.json.utf8))

        try good1.write(to: file)
        XCTAssertFalse(try DefaultConfig.writeIfMissing(at: file))
        XCTAssertEqual(try Data(contentsOf: file), good1, "existing user config is untouched")
    }
}
