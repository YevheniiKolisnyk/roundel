import XCTest
import ImageIO
import UniformTypeIdentifiers
import RoundelCore
@testable import RoundelWebP

/// What the user sees when a conversion goes wrong, through the real chain: executor -> image.convert -> batch
/// runner -> ImageBackends -> encoders -> toast. Generated images in a temporary directory only; nothing is shown on
/// screen, the "toast" is recorded.
@MainActor
final class ConversionFeedbackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-feedback-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Recording what the user would see

    private final class Screen: ActionReporting {
        private(set) var toasts: [(message: String, isError: Bool)] = []
        private(set) var progress: [String] = []
        private(set) var warnings: [String] = []
        /// Everything shown, in order: the last entry is what stays on screen.
        private(set) var shown: [String] = []
        func info(_ message: String) {}
        func warning(_ message: String) { warnings.append(message) }
        func toast(_ message: String, isError: Bool) { toasts.append((message, isError)); shown.append("toast: \(message)") }
        func progress(_ message: String) { progress.append(message); shown.append("progress: \(message)") }
    }

    private struct AllowEverything: PermissionChecking {
        func status(of permission: Permission) -> PermissionStatus { .granted }
        func request(_ permission: Permission) {}
    }

    private let screen = Screen()

    private func run(_ files: [URL], format: String, params: [String: JSONValue] = [:], backends: ImageBackends = ImageBackends([ImageIOEncoder(), WebPEncoder()])) async {
        let action = ImageConvertAction(converter: ImageConverter(encoder: backends), capabilities: backends)
        let executor = ActionExecutor(registry: ActionRegistry([action]), permissions: AllowEverything(), reporter: screen)
        var all = params
        all["format"] = .string(format)
        let node = ActionNode(id: "convert.\(format)", title: format.uppercased(), action: "image.convert", params: .object(all))
        await executor.execute(node, files: files)
        try? await Task.sleep(for: .milliseconds(50))   // progress messages hop to the main actor
    }

    // MARK: Generated files

    private func image(width: Int, height: Int, alpha: Bool = false) throws -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info))
        context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    @discardableResult
    private func write(_ image: CGImage, as type: UTType, named name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    // MARK: The reported bug

    func testAnImageTooWideForWebpTellsTheUserWhyAndLeavesNothingBehind() async throws {
        let wide = try write(try image(width: 17000, height: 100), as: .png, named: "wide.png")
        let before = try Data(contentsOf: wide)

        await run([wide], format: "webp")

        XCTAssertEqual(screen.toasts.count, 1, "exactly one message: \(screen.toasts)")
        let toast = try XCTUnwrap(screen.toasts.first)
        XCTAssertTrue(toast.isError)
        XCTAssertTrue(toast.message.contains("wide.png"), toast.message)
        XCTAssertTrue(toast.message.contains("too large for WebP (max 16383 pixels per side)"), toast.message)
        XCTAssertEqual(try listing(), ["wide.png"], "no empty or partial output, no temporary file")
        XCTAssertEqual(try Data(contentsOf: wide), before, "the original is untouched")
    }

    func testTheSameFileConvertsToJpegSoItIsOnlyTheWebpLimit() async throws {
        let wide = try write(try image(width: 17000, height: 100), as: .png, named: "wide.png")
        await run([wide], format: "jpeg")
        XCTAssertEqual(screen.toasts.map(\.message), ["Converted wide.png → wide.jpg"])
        XCTAssertEqual(try listing(), ["wide.jpg", "wide.png"])
    }

    // MARK: Batches

    func testInABatchTheOtherFilesStillConvertAndTheSummaryCountsTheFailure() async throws {
        let small = try image(width: 40, height: 20)
        var files = (1...5).map { try? write(small, as: .png, named: "ok\($0).png") }.compactMap { $0 }
        files.insert(try write(try image(width: 17000, height: 100), as: .png, named: "wide.png"), at: 2)

        await run(files, format: "webp")

        XCTAssertEqual(try listing().filter { $0.hasSuffix(".webp") }, (1...5).map { "ok\($0).webp" }, "the five good files converted, wide.png did not")
        let last = try XCTUnwrap(screen.toasts.last)
        XCTAssertTrue(last.isError, "a failure in the batch makes the summary an error-style toast")
        XCTAssertTrue(last.message.contains("Converted 5 of 6 files to WebP"), last.message)
        XCTAssertTrue(last.message.contains("1 failed: wide.png (too large for WebP (max 16383 pixels per side))"), last.message)
        XCTAssertEqual(screen.shown.last, "toast: \(last.message)", "nothing is shown after the summary, or it would replace it: \(screen.shown)")
    }

    func testTheSummaryIsAlwaysTheLastThingShownEvenForManyFiles() async throws {
        let small = try image(width: 16, height: 16)
        var files = (1...12).map { try? write(small, as: .png, named: String(format: "f%02d.png", $0)) }.compactMap { $0 }
        files.insert(try write(try image(width: 17000, height: 10), as: .png, named: "wide.png"), at: 6)
        for round in 1...15 {   // the ordering of background work is not deterministic, so look many times
            let again = Screen()
            let backends = ImageBackends([ImageIOEncoder(), WebPEncoder()])
            let action = ImageConvertAction(converter: ImageConverter(encoder: backends), capabilities: backends)
            let executor = ActionExecutor(registry: ActionRegistry([action]), permissions: AllowEverything(), reporter: again)
            await executor.execute(ActionNode(id: "c", title: "WebP", action: "image.convert", params: .object(["format": .string("webp")])), files: files)
            try? await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(again.shown.last?.hasPrefix("toast: Converted 12 of 13 files to WebP") ?? false, "round \(round): \(again.shown.suffix(3))")
            for file in try listing() where file.hasSuffix(".webp") { try FileManager.default.removeItem(at: dir.appendingPathComponent(file)) }
        }
    }

    // MARK: Every failure path ends in exactly one readable error toast and leaves the disk as it was

    private func expectOneErrorToast(_ parts: String..., file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(screen.toasts.count, 1, "exactly one message: \(screen.toasts)", file: file, line: line)
        let toast = try XCTUnwrap(screen.toasts.first, file: file, line: line)
        XCTAssertTrue(toast.isError, toast.message, file: file, line: line)
        for part in parts { XCTAssertTrue(toast.message.contains(part), "“\(part)” missing from: \(toast.message)", file: file, line: line) }
        XCTAssertFalse(toast.message.contains(".roundel-"), "internals leaked: \(toast.message)", file: file, line: line)
    }

    func testUnreadableInputSaysSo() async throws {
        let locked = try write(try image(width: 10, height: 10), as: .png, named: "locked.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        await run([locked], format: "webp")
        try expectOneErrorToast("locked.png", "can’t be read (no permission)")
    }

    func testAMissingFileSaysSo() async throws {
        await run([dir.appendingPathComponent("gone.png")], format: "webp")
        try expectOneErrorToast("gone.png", "file not found")
        XCTAssertEqual(try listing(), [])
    }

    func testAFileThatIsNotAnImageSaysSo() async throws {
        let text = dir.appendingPathComponent("notes.png")
        try Data("hello".utf8).write(to: text)
        await run([text], format: "webp")
        try expectOneErrorToast("notes.png", "not an image")
        XCTAssertEqual(try listing(), ["notes.png"])
    }

    func testADamagedImageSaysSoInsteadOfConvertingHalfOfIt() async throws {
        let whole = try write(try image(width: 300, height: 300), as: .png, named: "whole.png")
        let broken = dir.appendingPathComponent("broken.png")
        try Data(contentsOf: whole).prefix(200).write(to: broken)
        await run([broken], format: "webp")
        try expectOneErrorToast("broken.png", "damaged or incomplete")
        XCTAssertEqual(try listing(), ["broken.png", "whole.png"])
    }

    func testAReadOnlyFolderSaysSoAndNothingIsLeftBehind() async throws {
        let source = try write(try image(width: 10, height: 10), as: .png, named: "a.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        await run([source], format: "webp")
        try expectOneErrorToast("a.png", "no permission to save in this folder")
        XCTAssertEqual(try listing(), ["a.png"])
    }

    func testABatchWhereEverythingFailsGivesOneSummaryNamingThem() async throws {
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        try Data("x".utf8).write(to: a)
        try Data("y".utf8).write(to: b)
        let wide = try write(try image(width: 17000, height: 10), as: .png, named: "wide.png")
        await run([a, wide, b], format: "webp")
        try expectOneErrorToast("Couldn’t convert 3 files", "a.png (not an image)", "wide.png (too large for WebP (max 16383 pixels per side))")
    }

    // MARK: Backends that misbehave

    private struct SilentBackend: ImageBackend {
        let name = "silent"
        let writableTypeIdentifiers = ["public.png"]
        func detectType(of url: URL) -> String? { ImageIOEncoder().detectType(of: url) }
        func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome { EncodeOutcome() }
    }

    private struct FullDiskBackend: ImageBackend {
        let name = "full"
        let writableTypeIdentifiers = ["public.png"]
        func detectType(of url: URL) -> String? { ImageIOEncoder().detectType(of: url) }
        func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome { throw CocoaError(.fileWriteOutOfSpace) }
    }

    func testABackendThatReportsSuccessWithoutWritingIsNotTrusted() async throws {
        let source = try write(try image(width: 10, height: 10), as: .jpeg, named: "a.jpg")
        await run([source], format: "png", backends: ImageBackends([SilentBackend()]))
        try expectOneErrorToast("a.jpg", "the PNG encoder produced no output")
        XCTAssertEqual(try listing(), ["a.jpg"])
    }

    func testAFullDiskIsPutInWords() async throws {
        let source = try write(try image(width: 10, height: 10), as: .jpeg, named: "a.jpg")
        await run([source], format: "png", backends: ImageBackends([FullDiskBackend()]))
        try expectOneErrorToast("a.jpg", "not enough disk space")
        XCTAssertEqual(try listing(), ["a.jpg"])
    }

    func testAFormatNoBackendCanWriteIsRefusedUpFront() async throws {
        let source = try write(try image(width: 10, height: 10), as: .png, named: "a.png")
        await run([source], format: "webp", backends: ImageBackends([ImageIOEncoder()]))
        try expectOneErrorToast("WebP")
        XCTAssertEqual(try listing(), ["a.png"])
    }
}
