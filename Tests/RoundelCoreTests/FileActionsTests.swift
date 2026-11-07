import XCTest
@testable import RoundelCore

@MainActor
final class FileActionsTests: XCTestCase {
    private let fakes = Fakes()

    private func context(_ params: [String: JSONValue] = [:], files: [URL] = [], progress: @escaping @Sendable (String) -> Void = { _ in }) -> ActionContext {
        ActionContext(nodeID: "n", title: "Node", params: Params(.object(params)), files: files, reportProgress: progress)
    }

    private func failureMessage(_ block: () async throws -> ActionResult) async -> String? {
        do { _ = try await block(); return nil } catch let error as ActionError { return error.message } catch { return "\(error)" }
    }

    private let a = URL(fileURLWithPath: "/tmp/a.png")
    private let b = URL(fileURLWithPath: "/tmp/b.png")

    // MARK: file.openWith

    func testOpenWithTakesFilesAndDeclaresIt() {
        let action = FileOpenWithAction(workspace: fakes.workspace)
        XCTAssertEqual(action.id, "file.openWith")
        XCTAssertEqual(action.acceptedInputs, [.files])
        XCTAssertTrue(action.permissions.isEmpty)
    }

    func testOpenWithABundleId() async throws {
        let app = URL(fileURLWithPath: "/System/Applications/Preview.app")
        fakes.workspace.bundleIDs["com.apple.Preview"] = app
        _ = try await FileOpenWithAction(workspace: fakes.workspace).run(context(["bundleId": .string("com.apple.Preview")], files: [a, b]))
        XCTAssertEqual(fakes.workspace.openedFiles.count, 1)
        XCTAssertEqual(fakes.workspace.openedFiles.first?.urls, [a, b])
        XCTAssertEqual(fakes.workspace.openedFiles.first?.app, app)
    }

    func testOpenWithAnAppName() async throws {
        fakes.workspace.existing = ["/System/Applications/TextEdit.app"]
        _ = try await FileOpenWithAction(workspace: fakes.workspace).run(context(["name": .string("TextEdit")], files: [a]))
        XCTAssertEqual(fakes.workspace.openedFiles.first?.app.path, "/System/Applications/TextEdit.app")
    }

    func testOpenWithAnUnknownAppFails() async {
        let byName = await failureMessage { try await FileOpenWithAction(workspace: fakes.workspace).run(context(["name": .string("Nope")], files: [a])) }
        XCTAssertEqual(byName, "application “Nope” not found")
        let byID = await failureMessage { try await FileOpenWithAction(workspace: fakes.workspace).run(context(["bundleId": .string("x.y")], files: [a])) }
        XCTAssertEqual(byID, "no application with bundle id “x.y”")
        XCTAssertTrue(fakes.workspace.openedFiles.isEmpty)
    }

    func testOpenWithWithoutFilesFails() async {
        fakes.workspace.bundleIDs["x.y"] = URL(fileURLWithPath: "/Applications/X.app")
        let message = await failureMessage { try await FileOpenWithAction(workspace: fakes.workspace).run(context(["bundleId": .string("x.y")])) }
        XCTAssertEqual(message, "no files to open")
    }

    func testOpenWithNeedsExactlyOneOfNameAndBundleId() {
        let rules = FileOpenWithAction(workspace: fakes.workspace).paramRules
        XCTAssertTrue(rules.validate(.object([:]), actionID: "file.openWith").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["name": .string("A"), "bundleId": .string("b")]), actionID: "file.openWith").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["name": .string("A")]), actionID: "file.openWith").isEmpty)
    }

    func testOpenWithRejectsAPathAsTheName() {
        let issues = FileOpenWithAction(workspace: fakes.workspace).extraValidation(Params(.object(["name": .string("/Applications/X.app")])))
        XCTAssertTrue(issues.contains { $0.blocksRun })
    }

    func testOpenWithReportsAWorkspaceFailure() async {
        fakes.workspace.bundleIDs["x.y"] = URL(fileURLWithPath: "/Applications/X.app")
        fakes.workspace.failure = "could not open"
        let message = await failureMessage { try await FileOpenWithAction(workspace: fakes.workspace).run(context(["bundleId": .string("x.y")], files: [a])) }
        XCTAssertEqual(message, "could not open")
    }

    // MARK: image.convert

    private func convertAction(writable: [String]? = nil) -> ImageConvertAction {
        ImageConvertAction(converter: fakes.imageConverter, capabilities: FakeImageCapabilities(writable: writable))
    }

    func testImageConvertTakesFiles() {
        let action = convertAction()
        XCTAssertEqual(action.id, "image.convert")
        XCTAssertEqual(action.acceptedInputs, [.files])
        XCTAssertTrue(action.permissions.isEmpty)
    }

    func testFormatIsRequiredAndMustBeInTheCatalog() {
        let rules = convertAction().paramRules
        XCTAssertTrue(rules.validate(.object([:]), actionID: "image.convert").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["format": .string("jxl")]), actionID: "image.convert").contains { $0.blocksRun })
        XCTAssertTrue(rules.validate(.object(["format": .string("jpeg"), "quality": .number(0.8)]), actionID: "image.convert").isEmpty)
        XCTAssertTrue(rules.validate(.object(["format": .string("jpeg"), "quality": .number(2)]), actionID: "image.convert").contains { $0.blocksRun })
    }

    func testAFormatThisMacCannotWriteBlocksTheRun() {
        let action = convertAction(writable: ["public.png"])
        let issues = action.extraValidation(Params(.object(["format": .string("avif")])))
        XCTAssertTrue(issues.contains { $0.blocksRun && $0.message.contains("AVIF") }, "\(issues)")
        XCTAssertTrue(action.extraValidation(Params(.object(["format": .string("png")]))).isEmpty)
    }

    func testQualityOnALosslessFormatIsOnlyANote() {
        let issues = convertAction().extraValidation(Params(.object(["format": .string("png"), "quality": .number(0.5)])))
        XCTAssertEqual(issues.count, 1)
        XCTAssertFalse(issues[0].blocksRun)
    }

    func testRunPassesTheFilesFormatAndQualityToTheConverter() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.jpg"), notes: [])]
        _ = try await convertAction().run(context(["format": .string("jpeg"), "quality": .number(0.7)], files: [a]))
        let call = try XCTUnwrap(fakes.imageConverter.calls.first)
        XCTAssertEqual(call.files, [a])
        XCTAssertEqual(call.format.key, "jpeg")
        XCTAssertEqual(call.options.quality, 0.7)
    }

    func testQualityIsNotPassedForLosslessFormats() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.png"), notes: [])]
        _ = try await convertAction().run(context(["format": .string("png"), "quality": .number(0.7)], files: [a]))
        XCTAssertNil(fakes.imageConverter.calls.first?.options.quality)
    }

    func testSuccessIsAPlainMessage() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.jpg"), notes: [])]
        let result = try await convertAction().run(context(["format": .string("jpeg")], files: [a]))
        XCTAssertEqual(result, .message("Converted a.png → a.jpg"))
    }

    func testPartialFailureIsAWarning() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.jpg"), notes: []), .failed(source: b, message: "not an image")]
        let result = try await convertAction().run(context(["format": .string("jpeg")], files: [a, b]))
        XCTAssertEqual(result, .warning("Converted 1 of 2 files to JPEG · 1 failed: b.png (not an image)"))
    }

    func testTotalFailureThrows() async {
        fakes.imageConverter.results = [.failed(source: a, message: "not an image")]
        let message = await failureMessage { try await convertAction().run(context(["format": .string("jpeg")], files: [a])) }
        XCTAssertEqual(message, "Couldn’t convert a.png (not an image)")
    }

    func testProgressIsForwardedAsText() async throws {
        fakes.imageConverter.progressSteps = [(1, 3), (2, 3), (3, 3)]
        fakes.imageConverter.results = [.skipped(source: a, reason: .alreadyInFormat)]
        let log = TextLog()
        _ = try await convertAction().run(context(["format": .string("jpeg")], files: [a, b, a], progress: { log.add($0) }))
        XCTAssertEqual(log.lines, ["Converting 1/3", "Converting 2/3", "Converting 3/3"])
    }

    func testSingleFilesDoNotShowProgress() async throws {
        fakes.imageConverter.progressSteps = [(1, 1)]
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.jpg"), notes: [])]
        let log = TextLog()
        _ = try await convertAction().run(context(["format": .string("jpeg")], files: [a], progress: { log.add($0) }))
        XCTAssertTrue(log.lines.isEmpty)
    }

    func testRunWithoutFilesFails() async {
        let message = await failureMessage { try await convertAction().run(context(["format": .string("jpeg")])) }
        XCTAssertEqual(message, "no files to convert")
    }

    // MARK: lossless (WebP)

    func testLosslessMustBeABoolean() {
        let rules = convertAction().paramRules
        XCTAssertTrue(rules.validate(.object(["format": .string("webp"), "lossless": .bool(true)]), actionID: "image.convert").isEmpty)
        XCTAssertTrue(rules.validate(.object(["format": .string("webp"), "lossless": .string("yes")]), actionID: "image.convert").contains { $0.blocksRun })
    }

    func testLosslessOnAFormatWithoutALosslessModeIsOnlyANote() {
        let issues = convertAction().extraValidation(Params(.object(["format": .string("jpeg"), "lossless": .bool(true)])))
        XCTAssertEqual(issues.count, 1)
        XCTAssertFalse(issues[0].blocksRun)
        XCTAssertTrue(issues[0].message.contains("lossless"), issues[0].message)
        XCTAssertTrue(convertAction().extraValidation(Params(.object(["format": .string("webp"), "lossless": .bool(true)]))).isEmpty)
        XCTAssertTrue(convertAction().extraValidation(Params(.object(["format": .string("jpeg"), "lossless": .bool(false)]))).isEmpty, "false is the default, nothing to ignore")
    }

    func testWebpIsRefusedWhenNoBackendReportsIt() {
        let action = convertAction(writable: ["public.png"])
        XCTAssertTrue(action.extraValidation(Params(.object(["format": .string("webp")]))).contains { $0.blocksRun && $0.message.contains("WebP") })
    }

    func testRunPassesLosslessAndQualityForWebp() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.webp"), notes: [])]
        _ = try await convertAction().run(context(["format": .string("webp"), "lossless": .bool(true), "quality": .number(0.6)], files: [a]))
        XCTAssertEqual(fakes.imageConverter.calls.first?.options, ImageEncodingOptions(quality: 0.6, lossless: true))
    }

    func testWebpIsLossyUnlessAskedOtherwise() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.webp"), notes: [])]
        _ = try await convertAction().run(context(["format": .string("webp")], files: [a]))
        XCTAssertEqual(fakes.imageConverter.calls.first?.options, ImageEncodingOptions(quality: nil, lossless: false))
    }

    func testLosslessIsNotPassedToFormatsWithoutALosslessMode() async throws {
        fakes.imageConverter.results = [.converted(source: a, output: URL(fileURLWithPath: "/tmp/a.jpg"), notes: [])]
        _ = try await convertAction().run(context(["format": .string("jpeg"), "lossless": .bool(true), "quality": .number(0.5)], files: [a]))
        XCTAssertEqual(fakes.imageConverter.calls.first?.options, ImageEncodingOptions(quality: 0.5, lossless: false))
    }

    func testTheTimeoutGrowsWithTheNumberOfFiles() {
        let action = convertAction()
        let params = Params(.object(["format": .string("jpeg")]))
        XCTAssertLessThan(action.timeout(for: params, fileCount: 1), action.timeout(for: params, fileCount: 10))
        XCTAssertGreaterThanOrEqual(action.timeout(for: params, fileCount: 1), .seconds(30))
        XCTAssertLessThanOrEqual(action.timeout(for: params, fileCount: 100_000), .seconds(3600))
    }

    // MARK: Registry and generators

    func testTheRegistryKnowsTheFileActions() {
        let registry = ActionRegistry.standard(services: fakes.services)
        for id in ["file.openWith", "image.convert"] { XCTAssertTrue(registry.ids.contains(id), id) }
    }

    func testTheStandardGeneratorsIncludeTheImageFormats() {
        XCTAssertNotNil(NodeGeneratorRegistry.standard(services: fakes.services).generator(for: "image.convert.formats"))
    }

    func testTheDefaultConfigConvertsEveryOfferedFormat() {
        let resolved = ConfigResolver.resolve(DefaultConfig.config, generators: NodeGeneratorRegistry.standard(services: fakes.services))
        XCTAssertTrue(resolved.warnings.isEmpty, "\(resolved.warnings)")
        var formats: Set<String> = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if case .action(let action) = node, action.action == "image.convert", let key = Params(action.params).string("format") { formats.insert(key) }
                walk(node.children ?? [])
            }
        }
        walk(resolved.config.ring)
        XCTAssertEqual(formats, Set(ImageFormats.catalog.map(\.key)))
    }

    func testTheDefaultConfigHasAFilesGroupWithAnOpenWithExample() {
        let resolved = ConfigResolver.resolve(DefaultConfig.config, generators: NodeGeneratorRegistry.standard(services: fakes.services))
        XCTAssertNotNil(resolved.config.node(withID: "files"))
        func hasOpenWith(_ nodes: [Node]) -> Bool {
            nodes.contains { node in
                if case .action(let action) = node, action.action == "file.openWith" { return true }
                return hasOpenWith(node.children ?? [])
            }
        }
        XCTAssertTrue(hasOpenWith(resolved.config.ring))
    }

    private final class TextLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _lines: [String] = []
        var lines: [String] { lock.withLock { _lines } }
        func add(_ line: String) { lock.withLock { _lines.append(line) } }
    }
}

// MARK: Doubles

struct FakeImageCapabilities: ImageCapabilities {
    var writableTypeIdentifiers: [String]
    init(writable: [String]? = nil) {
        writableTypeIdentifiers = writable ?? ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp", "public.avif", "org.webmproject.webp"]
    }
}

final class FakeImageConverter: ImageConverting, @unchecked Sendable {
    struct Call { let files: [URL]; let format: ImageFormat; let options: ImageEncodingOptions }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var results: [ConversionItemResult] = []
    var progressSteps: [(Int, Int)] = []
    var calls: [Call] { lock.withLock { _calls } }

    func convert(files: [URL], to format: ImageFormat, options: ImageEncodingOptions, progress: @escaping @Sendable (Int, Int) -> Void) async -> [ConversionItemResult] {
        lock.withLock { _calls.append(Call(files: files, format: format, options: options)) }
        for (done, total) in progressSteps { progress(done, total) }
        return results
    }
}
