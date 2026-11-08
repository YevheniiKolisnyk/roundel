import Foundation

/// Whether an image file is whole. ImageIO decodes a truncated PNG or JPEG as a full image (the missing part comes out
/// grey) and still reports "complete", so the structure of those two formats is walked here. Formats that ImageIO
/// already refuses when damaged (TIFF, GIF, ...) get no opinion.
public enum ImageIntegrity {
    /// `true`/`false` for PNG and JPEG; `nil` for any other type.
    public static func isComplete(_ data: Data, detectedType: String) -> Bool? {
        switch detectedType {
        case "public.png": return pngIsComplete(data)
        case "public.jpeg": return jpegIsComplete(data)
        default: return nil
        }
    }

    /// Walks the chunks from the signature to IEND; a chunk that runs past the end of the data means truncation.
    static func pngIsComplete(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 20, Array(bytes[0..<8]) == signature else { return false }
        var offset = 8
        while offset + 12 <= bytes.count {   // length(4) type(4) data(length) crc(4)
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let isEnd = Array(bytes[offset + 4..<offset + 8]) == [0x49, 0x45, 0x4E, 0x44]   // "IEND"
            let next = offset + 12 + length
            guard next <= bytes.count else { return false }
            if isEnd { return true }
            offset = next
        }
        return false
    }

    /// Walks the segments of the first image, through every scan (progressive files have several), up to its EOI marker.
    /// Fill bytes, stuffed 0xFF00 and restart markers inside the entropy-coded data are skipped; a thumbnail's own EOI
    /// inside an EXIF segment is not mistaken for the end because segments are skipped by their length.
    static func jpegIsComplete(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return false }
        var i = 2
        while i + 1 < count {
            guard bytes[i] == 0xFF else { return false }          // between segments there must be a marker
            while i + 1 < count, bytes[i + 1] == 0xFF { i += 1 }   // fill bytes
            guard i + 1 < count else { return false }
            let marker = bytes[i + 1]
            switch marker {
            case 0xD9:
                return true                                         // EOI
            case 0x00, 0x01, 0xD0...0xD8:
                i += 2                                              // standalone markers
            case 0xDA:                                              // start of scan: header, then entropy-coded data
                guard i + 4 <= count else { return false }
                i += 2 + (Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]))
                while i + 1 < count {
                    if bytes[i] != 0xFF { i += 1; continue }
                    let next = bytes[i + 1]
                    if next == 0x00 || (0xD0...0xD7).contains(next) { i += 2; continue }
                    if next == 0xFF { i += 1; continue }
                    break                                           // a real marker follows the scan
                }
                if i + 1 >= count { return false }
            default:
                guard i + 4 <= count else { return false }
                i += 2 + (Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]))
                if i > count { return false }
            }
        }
        return false
    }
}
