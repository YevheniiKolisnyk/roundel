import XCTest
@testable import RoundelCore

final class OutputNamingTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/work/pics")

    private func name(_ source: String, _ ext: String, existing: Set<String> = [], reserved: Set<URL> = []) -> String {
        let source = dir.appendingPathComponent(source)
        let taken = Set(existing.map { dir.appendingPathComponent($0).path })
        return OutputNaming.destination(for: source, fileExtension: ext, exists: { taken.contains($0.path) }, reserved: reserved).lastPathComponent
    }

    func testTheOutputIsNextToTheSourceWithTheNewExtension() {
        let url = OutputNaming.destination(for: dir.appendingPathComponent("photo.png"), fileExtension: "jpg", exists: { _ in false })
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(url.lastPathComponent, "photo.jpg")
    }

    func testOnlyTheLastExtensionIsReplaced() {
        XCTAssertEqual(name("archive.tar.png", "jpg"), "archive.tar.jpg")
        XCTAssertEqual(name("IMG_0001.HEIC", "png"), "IMG_0001.png")
    }

    func testASourceWithoutExtensionGetsOne() {
        XCTAssertEqual(name("photo", "png"), "photo.png")
    }

    func testDotFilesKeepTheirName() {
        XCTAssertEqual(name(".hidden", "png"), ".hidden.png")
    }

    func testAnExistingFileGetsTheNextNumberLikeFinder() {
        XCTAssertEqual(name("photo.png", "jpg", existing: ["photo.jpg"]), "photo 2.jpg")
        XCTAssertEqual(name("photo.png", "jpg", existing: ["photo.jpg", "photo 2.jpg"]), "photo 3.jpg")
        XCTAssertEqual(name("photo.png", "jpg", existing: ["photo.jpg", "photo 2.jpg", "photo 3.jpg", "photo 4.jpg"]), "photo 5.jpg")
    }

    func testAGapInTheNumbersIsFilledInOrder() {
        XCTAssertEqual(name("photo.png", "jpg", existing: ["photo.jpg", "photo 3.jpg"]), "photo 2.jpg")
    }

    func testTheSourceItselfCountsAsTakenWhenTheNameWouldBeTheSame() {
        // A PNG stored as "a.png" that is converted to PNG-named output must not overwrite itself.
        XCTAssertEqual(name("a.png", "png", existing: ["a.png"]), "a 2.png")
    }

    func testNamesReservedByTheSameBatchAreAvoided() {
        let reserved: Set<URL> = [dir.appendingPathComponent("a.jpg")]
        XCTAssertEqual(name("a.gif", "jpg", reserved: reserved), "a 2.jpg")
    }

    func testReservationsIgnoreCaseBecauseTheVolumeUsuallyDoes() {
        let reserved: Set<URL> = [dir.appendingPathComponent("A.JPG")]
        XCTAssertEqual(name("a.gif", "jpg", reserved: reserved), "a 2.jpg")
    }

    func testReservedAndExistingNamesCombine() {
        let reserved: Set<URL> = [dir.appendingPathComponent("a 2.jpg")]
        XCTAssertEqual(name("a.gif", "jpg", existing: ["a.jpg"], reserved: reserved), "a 3.jpg")
    }

    func testUnicodeNamesSurvive() {
        XCTAssertEqual(name("світлина.png", "jpg", existing: ["світлина.jpg"]), "світлина 2.jpg")
    }

    func testNeverReturnsAnExistingName() {
        let existing = Set((["a.jpg"] + (2...50).map { "a \($0).jpg" }))
        XCTAssertEqual(name("a.png", "jpg", existing: existing), "a 51.jpg")
    }
}
