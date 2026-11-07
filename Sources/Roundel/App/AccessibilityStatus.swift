import ApplicationServices

/// Roundel does not prompt yet for Accessibility; it only reports the current trust state.
/// The prompt arrives with the first action that needs it (selected-text capture, window management).
enum AccessibilityStatus {
    static func logCurrent() {
        // Plain query: does NOT show the system prompt.
        let trusted = AXIsProcessTrusted()
        Log.info("Accessibility trusted: \(trusted) (not requested: no shipped action needs it yet)")
    }
}
