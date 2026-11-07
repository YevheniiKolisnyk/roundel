import AppKit
import ApplicationServices
import RoundelCore

/// Permission checks and requests. Requests happen only when an action that needs a permission is first used.
@MainActor
struct SystemPermissions: PermissionChecking {
    func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .automationSystemEvents:
            return automationStatus()
        }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // Shows the system prompt with a button that opens the right Settings pane.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .automationSystemEvents:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Asks macOS without prompting. Only an explicit "no" counts as denied; "not asked yet" lets the action run so
    /// the system prompt can appear.
    private func automationStatus() -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let descriptor = target.aeDesc else { return .notDetermined }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined   // -1744 (would ask), -600 (System Events not running), anything else
        }
    }
}
