import Foundation
import os

/// Minimal logger: unified log for Console.app, plus stderr so `swift run` shows output in the terminal.
enum Log {
    private static let logger = Logger(subsystem: "app.roundel", category: "main")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("[roundel] \(message)\n".utf8))
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("[roundel] WARNING: \(message)\n".utf8))
    }
}
