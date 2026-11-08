import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import RoundelCore
@testable import RoundelWebP

/// What the user sees when compressing, through the real chain: executor -> image.compress -> batch runner ->
/// ImageBackends -> encoders / PNG optimizer -> toast. Generated files in a temporary directory only; the "toast" is recorded.
@MainActor
final class CompressionFeedbackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-compress-feedback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private final class Screen: ActionReporting {
        private(set) var toasts: [(message: String, isError: Bool)] = []
        private(set) var kinds: [ToastKind] = []
        private(set) var progress: [String] = []
        func info(_ message: String) {}
        func warning(_ message: String) {}
        func toast(_ message: String, isError: Bool) { toasts.append((message, isError)) }
        func toast(_ message: String, kind: ToastKind) { kinds.append(kind); toasts.append((message, kind.isErrorStyle)) }
        func progress(_ message: String) { progress.append(message) }
    }
    private struct AllowEverything: PermissionChecking {
        func status(of permission: Permission) -> PermissionStatus { .granted }
        func request(_ permission: Permission) {}
    }
    private let screen = Screen()

    private func run(_ files: [URL], params: [String: JSONValue] = [:]) async {
        let backends = ImageBackends([ImageIOEncoder(), WebPEncoder()])
        let action = ImageCompressAction(compressor: ImageCompressor(encoder: backends))
        let executor = ActionExecutor(registry: ActionRegistry([action]), permissions: AllowEverything(), reporter: screen)
        await executor.execute(ActionNode(id: "c", title: "Compress", action: "image.compress", params: .object(params)), files: files)
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func picture(_ seed: UInt32) throws -> CGImage {
        var state = seed
        let w = 400, h = 300
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            state = state &* 1_664_525 &+ 1_013_904_223
            let n = Int(state >> 29) - 4
            let i = (y * w + x) * 4
            bytes[i] = UInt8(max(0, min(255, 100 + x * 150 / w + n))); bytes[i + 1] = UInt8(max(0, min(255, 80 + y * 120 / h + n))); bytes[i + 2] = UInt8(max(0, min(255, 200 - x * 100 / w + n)))
        } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @discardableResult
    private func write(_ image: CGImage, _ type: String, _ name: String, quality: Double? = nil) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(sink, image, quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary } ?? nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    private func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() }

    func testABatchEndsInOneSummaryWithTheTotalSavedAndShowsProgressOnTheWay() async throws {
        let files = try (1...3).map { try write(try picture(UInt32($0)), "public.jpeg", "p\($0).jpg", quality: 0.95) }
        await run(files)
        XCTAssertEqual(screen.progress, ["Compressing 1/3", "Compressing 2/3", "Compressing 3/3"])
        let last = try XCTUnwrap(screen.toasts.last)
        XCTAssertFalse(last.isError)
        XCTAssertTrue(last.message.hasPrefix("Compressed 3 files, saved "), last.message)
        XCTAssertTrue(last.message.contains(" → "), last.message)
        XCTAssertTrue(last.message.contains("%"), last.message)
        XCTAssertEqual(try names(), ["p1 compressed.jpg", "p1.jpg", "p2 compressed.jpg", "p2.jpg", "p3 compressed.jpg", "p3.jpg"])
    }

    func testAFailedFileIsNamedAndTheOthersStillGetCompressed() async throws {
        let good = try write(try picture(9), "public.jpeg", "good.jpg", quality: 0.95)
        let bad = dir.appendingPathComponent("notes.png")
        try Data("not an image".utf8).write(to: bad)
        let gif = dir.appendingPathComponent("anim.gif")
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for s in 1...2 { CGImageDestinationAddImage(sink, try picture(UInt32(s)), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(sink))

        await run([bad, good, gif])
        let last = try XCTUnwrap(screen.toasts.last)
        XCTAssertTrue(last.message.contains("Compressed 1 of 2 files"), last.message)
        XCTAssertTrue(last.message.contains("1 failed: notes.png (not an image)"), last.message)
        XCTAssertTrue(last.message.contains("anim.gif: animated, skipped (compressing would drop the animation)"), last.message)
        XCTAssertEqual(screen.kinds.last, .warning)
        XCTAssertTrue(try names().contains("good compressed.jpg"))
        XCTAssertFalse(try names().contains { $0.hasSuffix(".tmp") })
    }

    func testWhenNothingWorksTheErrorToastSaysWhyAndNothingIsLeftBehind() async throws {
        let bad = dir.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: bad)
        await run([bad])
        let last = try XCTUnwrap(screen.toasts.last)
        XCTAssertTrue(last.isError)
        XCTAssertEqual(last.message, "Compress Image: Couldn’t compress broken.jpg (not an image)")
        XCTAssertEqual(try names(), ["broken.jpg"])
    }

    func testAnAlreadyOptimalFileGetsAQuietNoteAndNoNewFile() async throws {
        let low = try write(try picture(4), "public.jpeg", "low.jpg", quality: 0.2)
        await run([low])
        XCTAssertEqual(screen.toasts.last?.message, "low.jpg is already optimal")
        XCTAssertEqual(screen.toasts.last?.isError, false)
        XCTAssertEqual(try names(), ["low.jpg"])
    }
}
