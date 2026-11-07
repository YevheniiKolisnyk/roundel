import Foundation

/// Mutes or unmutes the current output device through CoreAudio. Devices without a mute control (some HDMI, USB and
/// Bluetooth outputs) report that instead of silently doing nothing.
public struct MuteToggleAction: Action {
    public let id = "volume.muteToggle"
    public let title = "Mute"
    public let defaultIcon: Icon = .symbol("speaker.slash.fill")
    public var paramRules: ParamRules { ParamRules(specs: []) }

    private let mute: any MuteControlling

    public init(mute: any MuteControlling) {
        self.mute = mute
    }

    @MainActor
    public func isActive(params: Params) -> Bool? { mute.isMuted }

    public func run(_ context: ActionContext) async throws -> ActionResult {
        guard let muted = await mute.isMuted else {
            throw ActionError.failed("the current output device does not support mute")
        }
        try await mute.setMuted(!muted)
        return .message(muted ? "Unmuted" : "Muted")
    }
}
