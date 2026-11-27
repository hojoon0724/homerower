import CoreFoundation
import os
import Testing
@testable import HomeRower

/// The watchdog switches the tap off from its background queue when the main thread
/// stops sending heartbeats. These use a plain Mach port and a recording "disable"
/// action instead of a real event tap, which would need Accessibility access.
@Suite(.serialized)
struct TapWatchdogTests {
    /// Counts how often the watchdog tried to disable a tap.
    private final class DisableCounter: @unchecked Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    private func makePort() -> CFMachPort {
        CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, nil)
    }

    @Test func disablesTapWhenHeartbeatsStop() async throws {
        let counter = DisableCounter()
        let watchdog = TapWatchdog(disableTap: { _ in counter.increment() })
        watchdog.watch(makePort())

        // No heartbeats, as if the main thread were blocked.
        try await Task.sleep(for: .seconds(2.2))

        #expect(counter.value == 1, "should disable exactly once, not on every check")
        #expect(watchdog.takeDidTrip())
        #expect(!watchdog.takeDidTrip(), "the trip is reported once")
    }

    @Test func leavesTapAloneWhileHeartbeatsContinue() async throws {
        let counter = DisableCounter()
        let watchdog = TapWatchdog(disableTap: { _ in counter.increment() })
        watchdog.watch(makePort())

        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(200))
            watchdog.heartbeat()
        }

        #expect(counter.value == 0)
        #expect(!watchdog.takeDidTrip())
    }

    @Test func ignoresTapAfterWatchingStops() async throws {
        let counter = DisableCounter()
        let watchdog = TapWatchdog(disableTap: { _ in counter.increment() })
        watchdog.watch(makePort())
        // The tap was removed: the watchdog must not act on the old one.
        watchdog.watch(nil)

        try await Task.sleep(for: .seconds(2.2))

        #expect(counter.value == 0)
        #expect(!watchdog.takeDidTrip())
    }

    @Test func watchingANewTapClearsAnEarlierTrip() async throws {
        let counter = DisableCounter()
        let watchdog = TapWatchdog(disableTap: { _ in counter.increment() })
        watchdog.watch(makePort())
        try await Task.sleep(for: .seconds(2.2))
        #expect(counter.value == 1)

        // A restarted tap starts with a clean slate and a fresh heartbeat.
        watchdog.watch(makePort())
        #expect(!watchdog.takeDidTrip())
        try await Task.sleep(for: .milliseconds(500))
        #expect(counter.value == 1, "a fresh tap isn't disabled before the limit")
    }
}
