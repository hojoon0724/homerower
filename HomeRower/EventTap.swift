import AppKit
import CoreGraphics
import Observation
import os

/// Owns the CGEventTap and connects it to the engine and the emitter.
@Observable
final class EventTap {
    enum Status: Equatable {
        case stopped
        case waitingForPermission
        case running
    }

    /// A Privacy & Security setting the user has to turn on.
    enum Permission: Equatable {
        case accessibility
        case inputMonitoring
    }

    private(set) var status: Status = .stopped
    private(set) var logLines: [String] = []

    /// While waiting, the permission the user still needs to turn on. Accessibility is
    /// all an active keyboard tap needs; Input Monitoring is only asked for if the tap
    /// still can't be created once Accessibility is on.
    private(set) var neededPermission: Permission = .accessibility

    /// Access is on, but the tap still can't be created. This usually means a stale
    /// Privacy & Security entry, e.g. after rebuilding with a different signature.
    private(set) var isTapBlocked = false

    /// A permission reset is in progress.
    private(set) var isResettingPermission = false

    /// When off, every event passes through untouched.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { resetEngine() }
            log(isEnabled ? "Enabled" : "Disabled")
        }
    }

    /// Log every key event (kept in memory only).
    var logsKeyEvents = false

    /// Hold if the key is still down after this many milliseconds.
    var tappingTermMs: Double {
        didSet {
            UserDefaults.standard.set(tappingTermMs, forKey: Self.tappingTermKey)
            engine.settings.tappingTerm = tappingTermMs / 1000
        }
    }

    /// Typing-speed rule: tap if pressed within this many milliseconds of the last key (0 = off).
    var priorIdleMs: Double {
        didSet {
            UserDefaults.standard.set(priorIdleMs, forKey: Self.priorIdleKey)
            engine.settings.priorIdle = priorIdleMs / 1000
        }
    }

    /// Physical key → modifier it produces when held.
    var keyMap: [UInt16: Modifier] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: keyMap.map { (String($0.key), $0.value.rawValue) })
            UserDefaults.standard.set(stored, forKey: Self.keyMapKey)
            engine.settings.keyMap = keyMap
        }
    }

    /// The key Caps Lock acts as, or `nil` for normal Caps Lock.
    private(set) var capsLockTarget: UInt16?

    /// While the UI is recording a key, every event passes through untouched.
    @ObservationIgnored var isRecordingKey = false

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var engine = HoldTapEngine()
    @ObservationIgnored private let emitter = Emitter()
    @ObservationIgnored private var permissionWatcher: Task<Void, Never>?
    /// While running, checks that access is still on.
    @ObservationIgnored private var accessMonitor: Task<Void, Never>?
    /// Failed tap attempts in a row while access looked granted.
    @ObservationIgnored private var blockedAttempts = 0

    private static let maxLogLines = 500
    private static let tappingTermKey = "tappingTermMs"
    private static let priorIdleKey = "priorIdleMs"
    private static let keyMapKey = "keyMap"
    private static let capsLockTargetKey = "capsLockTarget"

    init() {
        let defaults = UserDefaults.standard
        tappingTermMs = defaults.object(forKey: Self.tappingTermKey) as? Double ?? Config.tappingTerm * 1000
        priorIdleMs = defaults.object(forKey: Self.priorIdleKey) as? Double ?? Config.priorIdle * 1000
        if let stored = defaults.dictionary(forKey: Self.keyMapKey) as? [String: String] {
            keyMap = stored.reduce(into: [:]) { map, entry in
                if let keyCode = UInt16(entry.key), let modifier = Modifier(rawValue: entry.value) {
                    map[keyCode] = modifier
                }
            }
        } else {
            keyMap = Config.homeRowMods
        }
        if let stored = defaults.object(forKey: Self.capsLockTargetKey) as? Int {
            capsLockTarget = UInt16(exactly: stored)
        }
        engine.settings = HoldTapEngine.Settings(
            tappingTerm: tappingTermMs / 1000,
            priorIdle: priorIdleMs / 1000,
            keyMap: keyMap
        )
    }

    func resetTimingsToDefaults() {
        tappingTermMs = Config.tappingTerm * 1000
        priorIdleMs = Config.priorIdle * 1000
    }

    /// Sets (or clears, with `nil`) the hold modifier for a physical key.
    func setModifier(_ modifier: Modifier?, for keyCode: UInt16) {
        keyMap[keyCode] = modifier
    }

    func resetKeyMapToDefaults() {
        keyMap = Config.homeRowMods
    }

    // MARK: - Caps Lock

    /// Makes Caps Lock act as another key, or restores it with `nil`.
    /// Returns `false` if the mapping couldn't be applied.
    @discardableResult
    func setCapsLockTarget(_ keyCode: UInt16?) -> Bool {
        let target = keyCode == CapsLockRemap.capsLockKeyCode ? nil : keyCode
        guard CapsLockRemap.apply(target: target) else {
            log("Failed to remap Caps Lock")
            return false
        }
        capsLockTarget = target
        if let target {
            UserDefaults.standard.set(Int(target), forKey: Self.capsLockTargetKey)
            log("Caps Lock now acts as \(KeyNames.name(for: target))")
        } else {
            UserDefaults.standard.removeObject(forKey: Self.capsLockTargetKey)
            log("Caps Lock restored")
        }
        return true
    }

    /// Re-applies the saved Caps Lock mapping (called at launch).
    func applyKeyRemapping() {
        guard let capsLockTarget else { return }
        if !CapsLockRemap.apply(target: capsLockTarget) {
            log("Failed to remap Caps Lock")
        }
    }

    /// Removes the Caps Lock mapping from the system without forgetting it (called at quit).
    func clearKeyRemapping() {
        guard capsLockTarget != nil else { return }
        CapsLockRemap.apply(target: nil)
    }

    // MARK: - Lifecycle

    /// Starts the tap if access is already on; otherwise waits for it without prompting.
    /// The UI asks for access when the user is ready.
    func start() {
        guard tap == nil else { return }
        if !tryStart() {
            log("Waiting for \(neededPermission == .accessibility ? "Accessibility" : "Input Monitoring") access…")
            waitForPermission()
        }
    }

    // MARK: - Permissions

    /// Gets HomeRower into the list in Privacy & Security so the user can turn it on.
    ///
    /// The first time, this asks macOS, which adds HomeRower to the list and shows its own
    /// alert with a button that opens the list, so the list isn't opened here as well.
    /// macOS only shows that alert once, so after that this opens the list directly.
    func requestPermission() {
        let promptedKey = Self.promptedKey(for: neededPermission)
        guard UserDefaults.standard.bool(forKey: promptedKey) else {
            UserDefaults.standard.set(true, forKey: promptedKey)
            switch neededPermission {
            case .accessibility:
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            case .inputMonitoring:
                _ = CGRequestListenEventAccess()
            }
            return
        }
        openPrivacySettings(neededPermission)
    }

    /// Remembers that macOS has already shown its alert for a permission.
    private static func promptedKey(for permission: Permission) -> String {
        switch permission {
        case .accessibility: "hasPromptedForAccessibility"
        case .inputMonitoring: "hasPromptedForInputMonitoring"
        }
    }

    /// Removes HomeRower from Privacy & Security and asks again. Fixes an entry that's
    /// on but no longer matches the app, which happens after rebuilding with ad-hoc signing.
    func resetPermission() async {
        guard let bundleID = Bundle.main.bundleIdentifier, !isResettingPermission else { return }
        isResettingPermission = true
        defer { isResettingPermission = false }

        for service in ["Accessibility", "PostEvent", "ListenEvent"] {
            let exitCode = await Self.runTCCUtil(["reset", service, bundleID])
            log("tccutil reset \(service): \(exitCode == 0 ? "ok" : "failed (\(exitCode))")")
        }
        // With the entries gone, macOS shows its alert again, so ask through it.
        for permission in [Permission.accessibility, .inputMonitoring] {
            UserDefaults.standard.removeObject(forKey: Self.promptedKey(for: permission))
        }
        neededPermission = .accessibility
        isTapBlocked = false
        blockedAttempts = 0
        requestPermission()
    }

    /// Tries to create the tap with the access that's on now, updating what's still needed.
    /// Returns `true` once the tap is running.
    private func tryStart() -> Bool {
        // Only try the tap once Accessibility is on. Trying earlier makes macOS ask for
        // Input Monitoring, which HomeRower usually doesn't need.
        guard AXIsProcessTrusted() else {
            neededPermission = .accessibility
            isTapBlocked = false
            blockedAttempts = 0
            return false
        }
        if createTap() { return true }

        blockedAttempts += 1
        if !CGPreflightListenEventAccess() {
            neededPermission = .inputMonitoring
        } else if blockedAttempts >= 4 {
            isTapBlocked = true
        }
        return false
    }

    /// Whether the access the running tap depends on is still on.
    private var hasRequiredAccess: Bool {
        guard AXIsProcessTrusted() else { return false }
        // Input Monitoring only matters if this Mac needed it to start the tap.
        return neededPermission != .inputMonitoring || CGPreflightListenEventAccess()
    }

    /// Checks once a second while running, so switching HomeRower off (or removing it)
    /// in Privacy & Security stops it right away instead of leaving a dead tap.
    private func monitorAccess() {
        accessMonitor?.cancel()
        accessMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if !self.hasRequiredAccess {
                    self.accessWasRevoked()
                    return
                }
            }
        }
    }

    /// Stops the tap and goes back to waiting, which brings back the permission screen.
    private func accessWasRevoked() {
        log("Access was turned off in Privacy & Security. Stopping until it's back on.")
        stop()
        // The entry may have been removed, not just switched off. macOS only adds it back
        // through its alert, so ask through the alert again next time.
        for permission in [Permission.accessibility, .inputMonitoring] {
            UserDefaults.standard.removeObject(forKey: Self.promptedKey(for: permission))
        }
        if !tryStart() {
            waitForPermission()
        }
    }

    /// Checks twice a second until the tap can be created, so turning access on in
    /// System Settings starts the app without quitting or pressing anything.
    private func waitForPermission() {
        status = .waitingForPermission
        guard permissionWatcher == nil else { return }
        permissionWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if self.tryStart() {
                    self.permissionWatcher = nil
                    return
                }
            }
        }
    }

    private nonisolated static func runTCCUtil(_ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = arguments
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    // MARK: - Tap

    /// Creates and installs the event tap. Returns `false` if the system refuses.
    private func createTap() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        permissionWatcher?.cancel()
        permissionWatcher = nil
        isTapBlocked = false
        blockedAttempts = 0
        status = .running
        log("Event tap running")
        monitorAccess()
        return true
    }

    func stop() {
        permissionWatcher?.cancel()
        permissionWatcher = nil
        accessMonitor?.cancel()
        accessMonitor = nil
        resetEngine()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        status = .stopped
    }

    func openPrivacySettings(_ permission: Permission) {
        let pane = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func clearLog() {
        logLines.removeAll()
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS also disables the tap when access is turned off. Don't fight that.
            guard hasRequiredAccess else {
                // Tear the tap down after this callback returns, not from inside it.
                Task { [weak self] in
                    guard let self, self.status == .running else { return }
                    self.accessWasRevoked()
                }
                return Unmanaged.passUnretained(event)
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("Tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), re-enabled")
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        // Our own posted events come back through the tap: leave them alone.
        if event.getIntegerValueField(.eventSourceUserData) == Config.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            emitter.hardwareFlags = event.flags
            emitter.applyFlags(to: event)
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled, !isRecordingKey, type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyEvent = KeyEvent(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            isDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        if logsKeyEvents {
            log(String(
                format: "%@ key %d%@  t=%.3f",
                keyEvent.isDown ? "↓" : "↑",
                keyEvent.keyCode,
                keyEvent.isRepeat ? " (repeat)" : "",
                keyEvent.timestamp
            ))
        }

        let actions = engine.handle(keyEvent)
        if perform(actions) {
            emitter.applyFlags(to: event)
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func timerFired(token: Int) {
        guard isEnabled else { return }
        _ = perform(engine.timerFired(token: token, at: ProcessInfo.processInfo.systemUptime))
    }

    /// Performs engine actions. Returns `true` if the current event should pass through.
    private func perform(_ actions: [EngineAction]) -> Bool {
        var passThrough = false
        for action in actions {
            switch action {
            case .passThrough:
                passThrough = true
            case let .key(keyCode, down, isRepeat):
                emitter.postKey(keyCode, down: down, isRepeat: isRepeat)
            case let .modifier(modifier, down):
                emitter.setModifier(modifier, down: down)
                if logsKeyEvents { log("\(down ? "Hold" : "Release") \(modifier.rawValue)") }
            case let .startTimer(token, delay):
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    self?.timerFired(token: token)
                }
            }
        }
        return passThrough
    }

    private func resetEngine() {
        _ = perform(engine.reset())
        emitter.releaseAllModifiers()
    }

    private func log(_ message: String) {
        logLines.append(message)
        if logLines.count > Self.maxLogLines {
            logLines.removeFirst(logLines.count - Self.maxLogLines)
        }
    }
}

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

    init() {
        let queue = DispatchQueue(label: "HomeRower.TapWatchdog", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
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
            CGEvent.tapEnable(tap: tapToDisable, enable: false)
        }
    }
}

/// C callback for the event tap. The tap is attached to the main run loop, so it
/// always runs on the main thread.
private nonisolated func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return MainActor.assumeIsolated {
        let eventTap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return eventTap.handle(type: type, event: event)
    }
}
