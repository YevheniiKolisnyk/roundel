import XCTest
@testable import RoundelCore

/// Failures reach the user as one short sentence; system errors are put in plain words and never mention internals.
final class ConversionFailureTextTests: XCTestCase {
    func testOurOwnErrorsKeepTheirText() {
        XCTAssertEqual(FailureText.describe(ImageConversionError.notAnImage), "not an image")
        XCTAssertEqual(FailureText.describe(ImageConversionError.damaged), "damaged or incomplete")
        XCTAssertEqual(FailureText.describe(ImageConversionError.noOutput(format: "WebP")), "the WebP encoder produced no output")
    }

    func testWritePermissionRunningOutOfSpaceAndReadOnlyVolumesAreNamed() {
        XCTAssertEqual(FailureText.describe(CocoaError(.fileWriteNoPermission)), "no permission to save in this folder")
        XCTAssertEqual(FailureText.describe(CocoaError(.fileWriteOutOfSpace)), "not enough disk space")
        XCTAssertEqual(FailureText.describe(CocoaError(.fileWriteVolumeReadOnly)), "the disk is read-only")
    }

    func testReadProblemsAreNamed() {
        XCTAssertEqual(FailureText.describe(CocoaError(.fileReadNoPermission)), "can’t be read (no permission)")
        XCTAssertEqual(FailureText.describe(CocoaError(.fileReadNoSuchFile)), "file not found")
        XCTAssertEqual(FailureText.describe(CocoaError(.fileNoSuchFile)), "file not found")
    }

    func testWriteErrorsFromPosixAreNamedToo() {
        XCTAssertEqual(FailureText.describe(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))), "no permission to save in this folder")
        XCTAssertEqual(FailureText.describe(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))), "not enough disk space")
        XCTAssertEqual(FailureText.describe(NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))), "the disk is read-only")
    }

    func testOtherErrorsUseTheSystemsSentenceButNeverOurTemporaryFileName() {
        let plain = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "The disk exploded."])
        XCTAssertEqual(FailureText.describe(plain), "The disk exploded.")
        let leaky = NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn’t save “.photo.webp.roundel-1A2B3C4D.tmp”."])
        XCTAssertEqual(FailureText.describe(leaky), "couldn’t save the file")
    }

    func testAnEmptyDescriptionIsNeverShownAsNothing() {
        let blank = NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "   "])
        XCTAssertEqual(FailureText.describe(blank), "unknown error")
    }
}
