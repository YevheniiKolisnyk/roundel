import Foundation

/// Failures reach the user as one short phrase after the file name ("wide.png (too large for WebP ...)"). System errors
/// are put in plain words here, and nothing internal (temporary file names, error domains) is ever shown.
public enum FailureText {
    public static let cannotRead = "can’t be read (no permission)"
    public static let cannotWriteHere = "no permission to save in this folder"

    public static func describe(_ error: Error) -> String {
        if let ours = error as? ImageConversionError { return ours.message }

        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: ns.code) {
            case .fileWriteNoPermission: return cannotWriteHere
            case .fileWriteOutOfSpace: return "not enough disk space"
            case .fileWriteVolumeReadOnly: return "the disk is read-only"
            case .fileReadNoPermission: return cannotRead
            case .fileReadNoSuchFile, .fileNoSuchFile: return "file not found"
            default: break
            }
        }
        if ns.domain == NSPOSIXErrorDomain {
            switch Int32(truncatingIfNeeded: ns.code) {
            case EACCES, EPERM: return cannotWriteHere
            case ENOSPC: return "not enough disk space"
            case EROFS: return "the disk is read-only"
            case ENOENT: return "file not found"
            default: break
            }
        }

        let text = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "unknown error" }
        if text.contains(".roundel-") { return "couldn’t save the file" }   // our temporary file's name is not for the user
        return text
    }
}
