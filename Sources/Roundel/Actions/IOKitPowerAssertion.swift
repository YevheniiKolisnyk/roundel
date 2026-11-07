import Foundation
import IOKit.pwr_mgt
import RoundelCore

/// One IOKit power assertion (not the `caffeinate` binary). The kernel drops it if Roundel exits, so it cannot leak.
@MainActor
final class IOKitPowerAssertion: PowerAssertionHolding {
    private var assertionID = IOPMAssertionID(0)
    private var autoRelease: Task<Void, Never>?
    private(set) var isHeld = false

    func acquire(mode: SleepPreventionMode, reason: String, releaseAfter: TimeInterval?) throws {
        release()

        let type = mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        guard status == kIOReturnSuccess else {
            throw ActionError.failed("could not create a power assertion (IOReturn \(status))")
        }
        assertionID = id
        isHeld = true

        if let releaseAfter {
            autoRelease = Task { [weak self] in
                try? await Task.sleep(for: .seconds(releaseAfter))
                guard !Task.isCancelled else { return }
                self?.release()
            }
        }
    }

    func release() {
        autoRelease?.cancel()
        autoRelease = nil
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isHeld = false
    }
}
