import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

/// That the presets keep the picture good enough, measured: structural similarity (SSIM) and PSNR between the source and
/// the compressed file, on generated pictures (tones, a hard edge, a thin line, a little grain) in a temporary directory.
final class CompressionQualityTests: TempDirTestCase {
    private let compressor = ImageCompressor(encoder: ImageIOEncoder())
    /// The floors the presets must stay above.
    private let floors: [CompressionPreset: Double] = [.light: 0.97, .balanced: 0.94, .strong: 0.90]

    private func compressed(_ source: URL, _ preset: CompressionPreset) async throws -> (url: URL, bytes: Int) {
        let results = await compressor.compress(files: [source], options: CompressionOptions(preset: preset), progress: { _, _ in })
        guard case .compressed(_, let output, _, let after)? = results.first else { XCTFail("\(preset): \(results)"); throw CancellationError() }
        return (output, after)
    }

    private func check(type: String, name: String, sourceQuality: Double) async throws {
        let source = try TestImages.write(TestImages.photo(width: 640, height: 480, grain: 2), as: type, to: dir.appendingPathComponent(name), quality: sourceQuality)
        let reference = try TestImages.load(source)
        var sizes: [Int] = []
        for preset in CompressionPreset.allCases {
            let (output, bytes) = try await compressed(source, preset)
            let image = try TestImages.load(output)
            let ssim = TestImages.ssim(reference, image)
            XCTAssertGreaterThanOrEqual(ssim, floors[preset] ?? 1, "\(type) \(preset): SSIM \(ssim)")
            XCTAssertGreaterThan(TestImages.psnr(reference, image), 30, "\(type) \(preset)")
            sizes.append(bytes)
            try FileManager.default.removeItem(at: output)
        }
        XCTAssertGreaterThanOrEqual(sizes[0], sizes[1], "\(type): Light is not smaller than Balanced: \(sizes)")
        XCTAssertGreaterThanOrEqual(sizes[1], sizes[2], "\(type): Balanced is not smaller than Strong: \(sizes)")
        XCTAssertLessThan(sizes[2], size(source), "\(type): Strong saves something")
    }

    func testJPEGPresetsKeepTheirSimilarityFloors() async throws {
        try await check(type: "public.jpeg", name: "cam.jpg", sourceQuality: 0.92)
    }

    func testHEICPresetsKeepTheirSimilarityFloors() async throws {
        XCTAssertTrue(SystemImageCapabilities().writableTypeIdentifiers.contains("public.heic"), "this Mac writes HEIC")
        try await check(type: "public.heic", name: "cam.heic", sourceQuality: 0.9)
    }

    func testTheSourceQualityCapKeepsALowerQualityJPEGFromGrowing() async throws {
        // A source at ImageIO 0.6 (IJG 87): Light's 0.70 would produce a bigger file; the cap lowers it so the result still shrinks.
        let source = try TestImages.write(TestImages.photo(width: 640, height: 480, grain: 2), as: "public.jpeg", to: dir.appendingPathComponent("mid.jpg"), quality: 0.6)
        let (output, bytes) = try await compressed(source, .light)
        XCTAssertLessThan(bytes, size(source))
        XCTAssertGreaterThanOrEqual(TestImages.ssim(try TestImages.load(source), try TestImages.load(output)), 0.90)
    }

    func testPNGIsBitForBitTheSamePicture() async throws {
        let source = try TestImages.write(TestImages.photo(width: 320, height: 240, grain: 2), as: "public.png", to: dir.appendingPathComponent("p.png"))
        for preset in CompressionPreset.allCases {
            let (output, _) = try await compressed(source, preset)
            XCTAssertEqual(TestImages.rgba(try TestImages.load(output)), TestImages.rgba(try TestImages.load(source)), "\(preset)")
            try FileManager.default.removeItem(at: output)
        }
    }

    func testTheMetricsThemselvesAreSane() throws {
        let a = TestImages.photo(width: 200, height: 150, grain: 0)
        XCTAssertEqual(TestImages.ssim(a, a), 1, accuracy: 1e-9)
        XCTAssertEqual(TestImages.psnr(a, a), 99)
        let noisy = TestImages.photo(width: 200, height: 150, grain: 40, seed: 5)
        XCTAssertLessThan(TestImages.ssim(a, noisy), 0.9)
        XCTAssertLessThan(TestImages.psnr(a, noisy), 30)
        let slight = TestImages.photo(width: 200, height: 150, grain: 1, seed: 5)
        XCTAssertGreaterThan(TestImages.ssim(a, slight), TestImages.ssim(a, noisy))
    }
}
