import IOKit.hid
import Observation

/// Watches the keyboard's raw key presses, before macOS applies key remapping (`hidutil`).
/// The event tap only sees keys after remapping, so this is what tells a remapped
/// Caps Lock apart from the key it acts as.
///
/// Needs Input Monitoring access. Without it nothing is watched and `isWatching` stays
/// `false`; it never asks for access itself.
@Observable
final class PhysicalKeyMonitor {
    private(set) var isWatching = false
    /// HID keyboard usages currently down.
    private var pressedUsages: Set<UInt32> = []
    @ObservationIgnored private var manager: IOHIDManager?

    /// Whether the physical key is down.
    func isDown(_ keyCode: UInt16) -> Bool {
        guard let usage = CapsLockRemap.hidUsage(for: keyCode) else { return false }
        return pressedUsages.contains(UInt32(usage))
    }

    func start() {
        guard manager == nil, !AppEnvironment.isPreview,
              IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboards = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, keyboards)
        IOHIDManagerRegisterInputValueCallback(manager, physicalKeyCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        self.manager = manager
        isWatching = true
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        isWatching = false
        pressedUsages = []
    }

    fileprivate func handle(usage: UInt32, isDown: Bool) {
        // Observers are notified on every assignment, so only assign on a real change.
        if isDown != pressedUsages.contains(usage) {
            if isDown { pressedUsages.insert(usage) } else { pressedUsages.remove(usage) }
        }
    }
}

/// C callback for HID input. The manager is scheduled on the main run loop, so it always
/// runs on the main thread.
private nonisolated func physicalKeyCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    let element = IOHIDValueGetElement(value)
    guard let context, IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad) else { return }
    // Real keys only: skips the rollover and reserved usages keyboards also report.
    let usage = IOHIDElementGetUsage(element)
    guard (0x04...0xE7).contains(usage) else { return }
    let isDown = IOHIDValueGetIntegerValue(value) != 0
    let monitor = Unmanaged<PhysicalKeyMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handle(usage: usage, isDown: isDown)
    }
}
