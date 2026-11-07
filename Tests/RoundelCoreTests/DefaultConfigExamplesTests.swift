import XCTest
@testable import RoundelCore

@MainActor
final class DefaultConfigExamplesTests: XCTestCase {
    private func allActionNodes(_ nodes: [Node]) -> [ActionNode] {
        nodes.flatMap { node -> [ActionNode] in
            switch node {
            case .action(let action): [action]
            case .group(let group): allActionNodes(group.children)
            }
        }
    }

    /// The default config as the ring sees it: with the generated groups filled in.
    private func resolvedDefault() -> RoundelConfig {
        ConfigResolver.resolve(DefaultConfig.config, generators: NodeGeneratorRegistry.standard(services: Fakes().services)).config
    }

    func testEveryRegisteredActionHasAnExampleInTheDefaultConfig() {
        let registry = ActionRegistry.standard(services: Fakes().services)
        let used = Set(allActionNodes(resolvedDefault().ring).map(\.action))
        for id in registry.ids {
            XCTAssertTrue(used.contains(id), "default config has no example for \(id)")
        }
    }

    func testDefaultConfigHasNoActionWarnings() {
        let registry = ActionRegistry.standard(services: Fakes().services)
        XCTAssertEqual(registry.warnings(for: resolvedDefault()), [])
    }

    func testDefaultConfigUsesNoUnknownActions() {
        let registry = ActionRegistry.standard(services: Fakes().services)
        for node in allActionNodes(resolvedDefault().ring) {
            // Registered, and usable either with or without a file drag (file actions are dimmed without one).
            XCTAssertTrue(registry.isAvailable(node) || registry.isAvailable(node, fileDrag: true), "\(node.id) -> \(node.action)")
        }
    }

    func testNodeIdsStayUniqueAcrossTheDefaultConfig() {
        let ids = allActionNodes(resolvedDefault().ring).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testDefaultConfigDocumentsTheOptionalSettings() {
        XCTAssertTrue(DefaultConfig.json.contains("login"))
        XCTAssertTrue(DefaultConfig.json.contains("Roundel Example"), "documents the Shortcut the examples expect")
    }

    // MARK: config.example.json

    func testExampleIsValidAndMarkedAsGenerated() throws {
        let config = try ConfigLoader.parse(Data(DefaultConfig.exampleJSON.utf8)).get()
        XCTAssertEqual(config, DefaultConfig.config)
        XCTAssertTrue(DefaultConfig.exampleJSON.contains("_generated"))
        XCTAssertTrue(DefaultConfig.exampleJSON.contains("regenerated"))
    }

    func testWriteExampleCreatesAndOverwritesButNeverTouchesConfigJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let userConfig = dir.appendingPathComponent("config.json")
        try Data("user content".utf8).write(to: userConfig)

        let example = try DefaultConfig.writeExample(in: dir)
        XCTAssertEqual(example.lastPathComponent, "config.example.json")
        XCTAssertEqual(try Data(contentsOf: example), Data(DefaultConfig.exampleJSON.utf8))

        try Data("stale".utf8).write(to: example)
        _ = try DefaultConfig.writeExample(in: dir)
        XCTAssertEqual(try Data(contentsOf: example), Data(DefaultConfig.exampleJSON.utf8), "regenerated on every launch")

        XCTAssertEqual(try Data(contentsOf: userConfig), Data("user content".utf8), "config.json is never touched")
    }

    func testWriteExampleCreatesTheFolderIfMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-tests-\(UUID().uuidString)/nested")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        XCTAssertNoThrow(try DefaultConfig.writeExample(in: dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.example.json").path))
    }
}
