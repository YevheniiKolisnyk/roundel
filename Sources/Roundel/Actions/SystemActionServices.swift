import RoundelCore
import RoundelWebP

/// Sends executor messages to the log and the toast.
@MainActor
struct AppActionReporter: ActionReporting {
    let toast: ToastPresenter

    func info(_ message: String) { Log.info(message) }
    func warning(_ message: String) { Log.warning(message) }
    func toast(_ message: String, isError: Bool) { toast.show(message, isError: isError) }
    func toast(_ message: String, kind: ToastKind) { toast.show(message, kind: kind) }
    func progress(_ message: String) { toast.showProgress(message) }
}

struct SystemActionLogger: ActionLogging {
    func info(_ message: String) { Log.info(message) }
    func warning(_ message: String) { Log.warning(message) }
}

extension ActionServices {
    /// The real implementations of every OS-facing protocol.
    @MainActor
    static func system() -> ActionServices {
        // ImageIO first: it keeps every format it can write; libwebp only adds WebP.
        let imageBackends = ImageBackends([ImageIOEncoder(), WebPEncoder()])
        return ActionServices(
            workspace: SystemWorkspace(),
            process: SystemProcessRunner(),
            power: IOKitPowerAssertion(),
            screenLocker: SACScreenLocker(),
            appearance: SystemAppearance(),
            mute: CoreAudioMute(),
            media: MediaKeyPoster(),
            selectedText: SelectedTextService(
                pasteboard: SystemPasteboard(), keys: CGEventKeystrokes(), modifiers: SystemModifierWatcher(),
                secureInput: SystemSecureInput(), clock: SystemAsyncClock()
            ),
            inputSources: SystemInputSources(),
            imageConverter: ImageConverter(encoder: imageBackends),
            imageCapabilities: imageBackends,
            logger: SystemActionLogger()
        )
    }
}
