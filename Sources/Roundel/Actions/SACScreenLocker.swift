import Foundation
import RoundelCore

/// Locks the screen through `SACLockScreenImmediate` from the private login.framework, looked up with dlsym so that
/// a future macOS without the symbol just reports "unavailable" and the action falls back to `pmset`.
@MainActor
final class SACScreenLocker: ScreenLocking {
    private typealias LockFunction = @convention(c) () -> Void

    private lazy var lockFunction: LockFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    func lockImmediately() -> Bool {
        guard let lockFunction else {
            Log.warning("SACLockScreenImmediate is not available on this macOS; falling back to pmset")
            return false
        }
        lockFunction()
        return true
    }
}
