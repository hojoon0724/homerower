import CoreGraphics
import Foundation
import os

/// Switches the tap off from a background thread if the main thread stops responding.
///
/// The tap is an active filter in front of all keyboard input, and it runs on the main
/// thread. If that thread hangs (or macOS stops serving the tap while it's still on),
/// every key press waits on HomeRower, and input to the whole Mac can freeze. A
/// disabled tap is skipped by the system, so switching it off from here always gives
/// input back, whatever the main thread is doing.
nonisolated final class TapWatchdog: @unchecked Sendable {
    private struct State {
        var tap: CFMachPort?
        var lastHeartbeat: UInt64 = 0
        var didTrip = false
    }

    /// How long the main thread may go without a heartbeat before the tap is switched off.
    private static let limit: UInt64 = 1_500_000_000 // 1.5 s, in nanoseconds

    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let timer: DispatchSourceTimer
    /// Switches a tap off. A parameter so tests can check the watchdog without a real tap.
    private let disableTap: @Sendable (CFMachPort) -> Void

    init(disableTap: @escaping @Sendable (CFMachPort) -> Void = { CGEvent.tapEnable(tap: $0, enable: false) }) {
        self.disableTap = disableTap
        let queue = DispatchQueue(label: "HomeRower.TapWatchdog", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    /// Starts (or, with `nil`, stops) watching a tap.
    func watch(_ tap: CFMachPort?) {
        let now = DispatchTime.now().uptimeNanoseconds
        state.withLockUnchecked { state in
            state.tap = tap
            state.lastHeartbeat = now
            state.didTrip = false
        }
    }

    /// Called regularly from the main thread to show it's still responding.
    func heartbeat() {
        let now = DispatchTime.now().uptimeNanoseconds
        state.withLockUnchecked { $0.lastHeartbeat = now }
    }

    /// Whether the watchdog switched the tap off since the last call.
    func takeDidTrip() -> Bool {
        state.withLockUnchecked { state in
            defer { state.didTrip = false }
            return state.didTrip
        }
    }

    private func check() {
        let now = DispatchTime.now().uptimeNanoseconds
        let tapToDisable: CFMachPort? = state.withLockUnchecked { state in
            guard let tap = state.tap, !state.didTrip,
                  now > state.lastHeartbeat, now - state.lastHeartbeat > Self.limit else { return nil }
            state.didTrip = true
            return tap
        }
        if let tapToDisable {
            disableTap(tapToDisable)
        }
    }
}
