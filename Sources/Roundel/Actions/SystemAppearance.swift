import AppKit
import RoundelCore

/// Reads the current appearance. Writing goes through AppleScript in `AppearanceToggleAction`.
@MainActor
struct SystemAppearance: AppearanceReading {
    var isDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
