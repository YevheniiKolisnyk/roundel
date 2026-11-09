import XCTest
@testable import RoundelCore

@MainActor
final class ImageCompressActionTests: XCTestCase {
    private let fakes = Fakes()
    private var action: ImageCompressAction { ImageCompressAction(compressor: fakes.imageCompressor) }
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/pics/\(name)") }

    private func context(_ params: JSONValue = .object([:]), files: [URL], progress: @escaping @Sendable (String) -> Void = { _ in }) -> ActionContext {
        ActionContext(nodeID: "n", title: "Compress", params: Params(params), files: files, reportProgress: progress)
    }

    // MARK: Declaration

    func testItsIdentityAndThatItNeedsFiles() {
        XCTAssertEqual(action.id, "image.compress")
        XCTAssertEqual(action.title, "Compress Image")
        XCTAssertEqual(action.acceptedInputs, [.files])
    }

    func testTheParamsAreValidated() {
        let rules = action.paramRules
        func issues(_ params: [String: JSONValue]) -> [ParamIssue] { rules.validate(.object(params), actionID: "image.compress") }
        XCTAssertTrue(issues([:]).isEmpty, "all optional: Balanced by default")
        XCTAssertTrue(issues(["preset": .string("light")]).isEmpty)
        XCTAssertTrue(issues(["preset": .string("extreme")]).contains { $0.blocksRun })
        XCTAssertTrue(issues(["quality": .number(1.5)]).contains { $0.blocksRun })
        XCTAssertTrue(issues(["quality": .number(0.6)]).isEmpty)
        XCTAssertTrue(issues(["maxDimension": .number(2048)]).isEmpty)
        XCTAssertTrue(issues(["maxDimension": .number(2)]).contains { $0.blocksRun })
        XCTAssertTrue(issues(["maxDimension": .number(1.5)]).contains { $0.blocksRun })
        XCTAssertTrue(issues(["stripMetadata": .string("yes")]).contains { $0.blocksRun })
        XCTAssertTrue(issues(["dropHDRData": .bool(true)]).isEmpty)
        XCTAssertTrue(issues(["reducePNGColors": .bool(false)]).isEmpty)
        XCTAssertTrue(issues(["reducePNGColors": .string("no")]).contains { $0.blocksRun })
        XCTAssertTrue(issues(["dropHDRData": .string("yes")]).contains { $0.blocksRun })
    }

    func testTheTimeoutGrowsWithTheNumberOfFiles() {
        XCTAssertEqual(action.timeout(for: Params(.object([:])), fileCount: 1), .seconds(60))
        XCTAssertEqual(action.timeout(for: Params(.object([:])), fileCount: 10), .seconds(330))
        XCTAssertEqual(action.timeout(for: Params(.object([:])), fileCount: 5000), .seconds(3600))
    }

    // MARK: Running

    func testItPassesTheFilesAndTheOptionsToTheCompressor() async throws {
        fakes.imageCompressor.results = [.compressed(source: url("a.jpg"), output: url("a compressed.jpg"), bytesBefore: 2_000_000, bytesAfter: 1_000_000)]
        let params: JSONValue = .object(["preset": .string("strong"), "quality": .number(0.3), "maxDimension": .number(1600), "stripMetadata": .bool(true), "dropHDRData": .bool(true)])
        _ = try await action.run(context(params, files: [url("a.jpg")]))
        let call = try XCTUnwrap(fakes.imageCompressor.calls.first)
        XCTAssertEqual(call.files, [url("a.jpg")])
        XCTAssertEqual(call.options, CompressionOptions(preset: .strong, quality: 0.3, maxDimension: 1600, stripMetadata: true, dropHDRData: true))
    }

    func testTheResultIsTheBatchSummary() async throws {
        fakes.imageCompressor.results = [.compressed(source: url("a.jpg"), output: url("a compressed.jpg"), bytesBefore: 2_000_000, bytesAfter: 1_000_000)]
        let result = try await action.run(context(files: [url("a.jpg")]))
        XCTAssertEqual(result, .message("Compressed a.jpg → a compressed.jpg, saved 50% (2.0 MB → 1.0 MB)"))
    }

    func testAPartialFailureIsAWarningAndATotalFailureIsAnError() async throws {
        fakes.imageCompressor.results = [.compressed(source: url("a.jpg"), output: url("a compressed.jpg"), bytesBefore: 1000, bytesAfter: 500), .failed(source: url("b.png"), message: "damaged or incomplete")]
        let partial = try await action.run(context(files: [url("a.jpg"), url("b.png")]))
        guard case .warning(let text) = partial else { return XCTFail("\(partial)") }
        XCTAssertTrue(text.contains("b.png (damaged or incomplete)"))

        fakes.imageCompressor.results = [.failed(source: url("b.png"), message: "damaged or incomplete")]
        do { _ = try await action.run(context(files: [url("b.png")])); XCTFail("should throw") } catch let error as ActionError {
            XCTAssertEqual(error, .failed("Couldn’t compress b.png (damaged or incomplete)"))
        }
    }

    func testNothingToDoIsAQuietMessageNotAnError() async throws {
        fakes.imageCompressor.results = [.alreadyOptimal(source: url("a.jpg"))]
        let result = try await action.run(context(files: [url("a.jpg")]))
        XCTAssertEqual(result, .info("a.jpg is already optimal"), "nothing was compressed and nothing went wrong: neutral, not a success")
    }

    func testProgressIsReportedOnlyForSeveralFiles() async throws {
        fakes.imageCompressor.progressSteps = [(1, 2), (2, 2)]
        fakes.imageCompressor.results = [.alreadyOptimal(source: url("a.jpg")), .alreadyOptimal(source: url("b.jpg"))]
        let seen = Lines()
        _ = try await action.run(context(files: [url("a.jpg"), url("b.jpg")], progress: { seen.add($0) }))
        XCTAssertEqual(seen.values, ["Compressing 1/2", "Compressing 2/2"])

        fakes.imageCompressor.results = [.alreadyOptimal(source: url("a.jpg"))]
        let single = Lines()
        _ = try await action.run(context(files: [url("a.jpg")], progress: { single.add($0) }))
        XCTAssertEqual(single.values, [])
    }

    func testNoFilesAndAMismatchedReportAreErrors() async {
        do { _ = try await action.run(context(files: [])); XCTFail() } catch let error as ActionError { XCTAssertEqual(error, .failed("no files to compress")) } catch { XCTFail("\(error)") }
        fakes.imageCompressor.results = []
        do { _ = try await action.run(context(files: [url("a.jpg")])); XCTFail() } catch let error as ActionError { XCTAssertEqual(error, .failed("the compressor reported on 0 of 1 files")) } catch { XCTFail("\(error)") }
    }

    // MARK: The group of presets

    func testThePresetsAreGeneratedAsThreeActionsWithSymbolsAndTheirPresetParam() {
        let group = GroupNode(id: "files.compress", title: "Compress", children: [], generate: "image.compress.presets", params: .object(["maxDimension": .number(2000), "stripMetadata": .bool(true), "dropHDRData": .bool(true), "reducePNGColors": .bool(false), "quality": .number(0.1)]))
        let nodes = ImageCompressPresetsGenerator().children(for: group)
        XCTAssertEqual(nodes.map(\.id), ["files.compress.light", "files.compress.balanced", "files.compress.strong"])
        XCTAssertEqual(nodes.map(\.title), ["Light", "Balanced", "Strong"])
        for (node, preset) in zip(nodes, CompressionPreset.allCases) {
            guard case .action(let a) = node else { return XCTFail() }
            XCTAssertEqual(a.action, "image.compress")
            XCTAssertEqual(Params(a.params).string("preset"), preset.rawValue)
            XCTAssertEqual(Params(a.params).int("maxDimension"), 2000)
            XCTAssertEqual(Params(a.params).bool("stripMetadata"), true)
            XCTAssertEqual(Params(a.params).bool("dropHDRData"), true)
            XCTAssertEqual(Params(a.params).bool("reducePNGColors"), false)
            XCTAssertNil(Params(a.params).double("quality"), "a quality on the group would make the three presets identical")
            guard case .symbol(let name)? = a.icon else { return XCTFail("a symbol: the title is too long for a cell and is shown in the middle") }
            XCTAssertTrue(name.hasPrefix("gauge.with.dots.needle."))
            if preset == .strong { XCTAssertEqual(name, "gauge.with.dots.needle.100percent", "the maximum") }
        }
        XCTAssertEqual(Set(nodes.compactMap { node -> String? in if case .action(let a) = node, case .symbol(let s)? = a.icon { s } else { nil } }).count, 3, "three different symbols")
    }

    func testASkippedBatchIsNeutralInfoAndASkipAloneIsNotASuccess() async throws {
        fakes.imageCompressor.results = [.skipped(source: url("a.jpg"), reason: .hasAuxiliaryData([.hdrGainMap]))]
        let skipped = try await action.run(context(files: [url("a.jpg")]))
        XCTAssertEqual(skipped, .info("Nothing to compress · a.jpg: has an HDR gain map, skipped (set dropHDRData to compress anyway)"))

        fakes.imageCompressor.results = [.alreadyOptimal(source: url("a.jpg")), .skipped(source: url("b.gif"), reason: .animated)]
        guard case .info = try await action.run(context(files: [url("a.jpg"), url("b.gif")])) else { return XCTFail("info") }

        // Real savings stay a success, partial failure a warning, total failure an error.
        fakes.imageCompressor.results = [.compressed(source: url("a.jpg"), output: url("a compressed.jpg"), bytesBefore: 100, bytesAfter: 50), .skipped(source: url("b.gif"), reason: .animated)]
        guard case .message = try await action.run(context(files: [url("a.jpg"), url("b.gif")])) else { return XCTFail("success") }
    }

    func testTheGeneratorAndTheActionAreRegistered() {
        XCTAssertNotNil(NodeGeneratorRegistry.standard(services: fakes.services).generator(for: "image.compress.presets"))
        XCTAssertTrue(ActionRegistry.standard(services: fakes.services).ids.contains("image.compress"))
    }

    func testTheDefaultConfigHasACompressGroupNextToConvertAndDocumentsIt() throws {
        guard case .group(let files)? = DefaultConfig.config.ring.first(where: { $0.id == "files" }) else { return XCTFail("no Files group") }
        XCTAssertEqual(files.children.prefix(2).map(\.id), ["files.convert", "files.compress"])
        guard case .group(let compress) = files.children[1] else { return XCTFail() }
        XCTAssertEqual(compress.generate, "image.compress.presets")
        XCTAssertNil(Params(compress.params).bool("stripMetadata"), "an explicit false here would stop Strong from stripping")
        XCTAssertNil(Params(compress.params).bool("dropHDRData"))
        XCTAssertNil(Params(compress.params).bool("reducePNGColors"))
        for needle in ["image.compress", "stripMetadata", "dropHDRData", "reducePNGColors", "256 colors", "gain map", "set dropHDRData to compress anyway", "maxDimension", "already optimal", "XMP", "MakerNote", "metadata removed", "wins over the preset", "GPS", "orientation", "at least 2%", "compressed"] {
            XCTAssertTrue(DefaultConfig.exampleJSON.contains(needle), "the example config explains: \(needle)")
        }
    }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    var values: [String] { lock.withLock { _values } }
    func add(_ s: String) { lock.withLock { _values.append(s) } }
}
