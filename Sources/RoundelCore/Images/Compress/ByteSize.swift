import Foundation

/// File sizes as people read them (decimal units, like Finder), and "how much was saved".
public enum ByteSize {
    public static func format(_ bytes: Int) -> String {
        if bytes < 1000 { return bytes == 1 ? "1 byte" : "\(max(bytes, 0)) bytes" }
        let kilobytes = Double(bytes) / 1000
        if kilobytes.rounded() < 1000 { return "\(Int(kilobytes.rounded())) KB" }
        let megabytes = Double(bytes) / 1_000_000
        if (megabytes * 10).rounded() / 10 < 1000 { return String(format: "%.1f MB", megabytes) }
        return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }

    /// Whole percent saved, rounded down, never negative: it never claims more than it saved.
    public static func savedPercent(before: Int, after: Int) -> Int {
        guard before > 0, after < before else { return 0 }
        return (before - after) * 100 / before
    }
}
