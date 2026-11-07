import XCTest
@testable import RoundelCore

/// Groups that build their children from a runtime list ("generate"), and the schema changes around them.
final class NodeGenerationTests: XCTestCase {
    private struct FakeCapabilities: ImageCapabilities {
        var writableTypeIdentifiers: [String]
    }

    private let allWritable = ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp", "public.avif"]

    private func generators(writable: [String]? = nil) -> NodeGeneratorRegistry {
        NodeGeneratorRegistry([ImageConvertFormatsGenerator(capabilities: FakeCapabilities(writableTypeIdentifiers: writable ?? allWritable))])
    }

    private func decodeConfig(_ ring: String) throws -> RoundelConfig {
        try ConfigLoader.parse(Data(#"{"version": 1, "ring": \#(ring)}"#.utf8)).get()
    }

    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }

    private func generatedGroup(children: [Node] = [], params: JSONValue = .object([:]), generate: String = "image.convert.formats") -> Node {
        .group(GroupNode(id: "convert", title: "Convert", children: children, generate: generate, params: params))
    }

    // MARK: Schema

    func testAGroupMayHaveGenerateInsteadOfChildren() throws {
        let config = try decodeConfig(#"[{"type": "group", "id": "c", "title": "C", "generate": "image.convert.formats", "params": {"quality": 0.8}}]"#)
        guard case .group(let group) = config.ring[0] else { return XCTFail() }
        XCTAssertEqual(group.generate, "image.convert.formats")
        XCTAssertEqual(group.children, [])
        XCTAssertEqual(Params(group.params).double("quality"), 0.8)
    }

    func testAGroupWithNeitherChildrenNorGenerateIsStillAnError() {
        let result = ConfigLoader.parse(Data(#"{"version": 1, "ring": [{"type": "group", "id": "c", "title": "C"}]}"#.utf8))
        guard case .failure = result else { return XCTFail("expected an error") }
    }

    func testAnEmptyChildrenListWithoutGenerateIsStillAnError() {
        let result = ConfigLoader.parse(Data(#"{"version": 1, "ring": [{"type": "group", "id": "c", "title": "C", "children": []}]}"#.utf8))
        guard case .failure = result else { return XCTFail("expected an error") }
    }

    func testOldConfigsWithoutTheNewKeysDecodeExactlyAsBefore() throws {
        let config = try decodeConfig(#"[{"type": "group", "id": "g", "title": "G", "children": [{"type": "action", "id": "a", "title": "A", "action": "log"}]}]"#)
        guard case .group(let group) = config.ring[0] else { return XCTFail() }
        XCTAssertNil(group.generate)
        XCTAssertEqual(group.params, .object([:]))
        XCTAssertEqual(group.children.count, 1)
    }

    func testGenerateAndParamsSurviveEncoding() throws {
        let config = RoundelConfig(ring: [generatedGroup(params: .object(["quality": .number(0.9)]))])
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(RoundelConfig.self, from: data), config)
    }

    func testGenerateMustBeAString() {
        let result = ConfigLoader.parse(Data(#"{"version": 1, "ring": [{"type": "group", "id": "c", "title": "C", "generate": 5}]}"#.utf8))
        guard case .failure = result else { return XCTFail("expected an error") }
    }

    // MARK: Resolving

    func testAGeneratedGroupGetsOneActionPerAvailableFormat() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators())
        guard case .group(let group)? = resolved.config.ring.first else { return XCTFail() }
        XCTAssertEqual(group.children.map(\.id), ["convert.png", "convert.jpeg", "convert.heic", "convert.tiff", "convert.gif", "convert.bmp", "convert.avif"])
        XCTAssertEqual(group.children.map(\.title), ["PNG", "JPEG", "HEIC", "TIFF", "GIF", "BMP", "AVIF"])
        XCTAssertTrue(resolved.warnings.isEmpty)
    }

    func testGeneratedChildrenAreImageConvertActionsWithTheirFormat() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators())
        guard case .group(let group)? = resolved.config.ring.first, case .action(let png) = group.children[0] else { return XCTFail() }
        XCTAssertEqual(png.action, "image.convert")
        XCTAssertEqual(Params(png.params).string("format"), "png")
        XCTAssertEqual(png.icon, .text("PNG"), "the ring draws icons, so each format needs its own")
    }

    func testOnlyWhatTheSystemCanWriteIsGenerated() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators(writable: ["public.png", "public.jpeg", "public.pdf"]))
        guard case .group(let group)? = resolved.config.ring.first else { return XCTFail() }
        XCTAssertEqual(group.children.map(\.title), ["PNG", "JPEG"])
    }

    func testTheGroupsQualityIsPassedToLossyFormatsOnly() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup(params: .object(["quality": .number(0.7)]))]), generators: generators())
        guard case .group(let group)? = resolved.config.ring.first else { return XCTFail() }
        for child in group.children {
            guard case .action(let node) = child else { return XCTFail() }
            let format = ImageFormats.format(forKey: Params(node.params).string("format") ?? "")!
            XCTAssertEqual(Params(node.params).double("quality"), format.isLossy ? 0.7 : nil, format.key)
        }
    }

    func testWebpGetsQualityAndLosslessFromTheGroup() {
        let caps = allWritable + ["org.webmproject.webp"]
        let group = generatedGroup(params: .object(["quality": .number(0.6), "lossless": .bool(true)]))
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [group]), generators: generators(writable: caps))
        guard case .group(let g)? = resolved.config.ring.first else { return XCTFail() }
        let nodes = g.children.compactMap { child -> ActionNode? in if case .action(let a) = child { return a }; return nil }
        let webp = nodes.first { Params($0.params).string("format") == "webp" }
        XCTAssertEqual(webp?.title, "WebP")
        XCTAssertEqual(webp?.icon, .text("WebP"))
        XCTAssertEqual(Params(webp?.params ?? .null).double("quality"), 0.6)
        XCTAssertEqual(Params(webp?.params ?? .null).bool("lossless"), true)
        for other in nodes where Params(other.params).string("format") != "webp" {
            XCTAssertNil(Params(other.params).bool("lossless"), "only formats with a lossless mode get it: \(other.id)")
        }
    }

    func testLosslessThatIsNotABooleanIsIgnored() {
        let group = generatedGroup(params: .object(["lossless": .string("yes")]))
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [group]), generators: generators(writable: ["org.webmproject.webp"]))
        guard case .group(let g)? = resolved.config.ring.first, case .action(let webp) = g.children[0] else { return XCTFail() }
        XCTAssertNil(Params(webp.params).bool("lossless"))
    }

    func testNoQualityMeansNoQualityParam() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators())
        guard case .group(let group)? = resolved.config.ring.first, case .action(let jpeg) = group.children[1] else { return XCTFail() }
        XCTAssertNil(Params(jpeg.params).double("quality"))
    }

    func testStaticChildrenComeFirstAndAreKept() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup(children: [action("mine")])]), generators: generators(writable: ["public.png"]))
        guard case .group(let group)? = resolved.config.ring.first else { return XCTFail() }
        XCTAssertEqual(group.children.map(\.id), ["mine", "convert.png"])
    }

    func testAGeneratedIdThatAStaticChildAlreadyUsesIsSkipped() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup(children: [action("convert.png")])]), generators: generators(writable: ["public.png", "public.jpeg"]))
        guard case .group(let group)? = resolved.config.ring.first else { return XCTFail() }
        XCTAssertEqual(group.children.map(\.id), ["convert.png", "convert.jpeg"])
        XCTAssertEqual(group.children[0].title, "convert.png", "the static one wins")
    }

    func testNestedGeneratedGroupsAreResolved() {
        let inner = generatedGroup()
        let outer = Node.group(GroupNode(id: "files", title: "Files", children: [inner]))
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [outer]), generators: generators(writable: ["public.png"]))
        guard case .group(let files)? = resolved.config.ring.first, case .group(let convert) = files.children[0] else { return XCTFail() }
        XCTAssertEqual(convert.children.map(\.id), ["convert.png"])
    }

    func testResolvingClearsGenerateSoItCannotBeAppliedTwice() {
        let once = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators())
        let twice = ConfigResolver.resolve(once.config, generators: generators())
        XCTAssertEqual(once.config, twice.config)
        guard case .group(let group)? = once.config.ring.first else { return XCTFail() }
        XCTAssertNil(group.generate)
    }

    func testConfigsWithoutGenerateAreReturnedUnchanged() throws {
        let config = RoundelConfig(ring: [.group(GroupNode(id: "g", title: "G", children: [action("a")])), action("b")])
        let resolved = ConfigResolver.resolve(config, generators: generators())
        XCTAssertEqual(resolved.config, config)
        XCTAssertTrue(resolved.warnings.isEmpty)
    }

    func testAnUnknownGeneratorIsAWarningAndLeavesTheGroupEmpty() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup(generate: "nope.thing")]), generators: generators())
        XCTAssertEqual(resolved.warnings.map(\.nodeID), ["convert"])
        XCTAssertTrue(resolved.warnings[0].message.contains("nope.thing"), resolved.warnings[0].message)
        guard case .group(let group)? = resolved.config.ring.first else { return XCTFail() }
        XCTAssertEqual(group.children, [])
    }

    func testAGeneratorThatProducesNothingIsAWarning() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators(writable: []))
        XCTAssertEqual(resolved.warnings.map(\.nodeID), ["convert"])
        XCTAssertTrue(resolved.warnings[0].message.contains("no items"), resolved.warnings[0].message)
    }

    func testResolvingDoesNotTouchSettingsOrVersion() {
        let settings = ConfigSettings(openMode: .clickRequired, expandDelayMs: 300)
        let resolved = ConfigResolver.resolve(RoundelConfig(version: 1, settings: settings, ring: [generatedGroup()]), generators: generators())
        XCTAssertEqual(resolved.config.settings, settings)
        XCTAssertEqual(resolved.config.version, 1)
    }

    func testResolvedNodesCanBeLookedUpByID() {
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [generatedGroup()]), generators: generators())
        XCTAssertNotNil(resolved.config.node(withID: "convert.heic"))
    }

    // MARK: Validation

    func testTheValidatorAcceptsAnEmptyGroupThatGenerates() throws {
        let config = try decodeConfig(#"[{"type": "group", "id": "c", "title": "C", "generate": "image.convert.formats"}]"#)
        XCTAssertEqual(config.ring.count, 1)
    }

    func testIdsOfGeneratedNodesDoNotClashAcrossGroups() {
        let a = Node.group(GroupNode(id: "a", title: "A", children: [], generate: "image.convert.formats"))
        let b = Node.group(GroupNode(id: "b", title: "B", children: [], generate: "image.convert.formats"))
        let resolved = ConfigResolver.resolve(RoundelConfig(ring: [a, b]), generators: generators(writable: ["public.png"]))
        var ids: [String] = []
        func walk(_ nodes: [Node]) { for node in nodes { ids.append(node.id); walk(node.children ?? []) } }
        walk(resolved.config.ring)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
