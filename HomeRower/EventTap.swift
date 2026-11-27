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

    /// Why HomeRower stopped its own tap to give keyboard input back.
    enum FailSafeReason: Equatable {
        /// A permission check reported that access is off.
        case accessRevoked
        /// Posted events stopped coming back: macOS is rejecting them.
        case postingBlocked
        /// macOS kept disabling the tap, or it was disabled and couldn't be re-enabled.
        case tapDisabledRepeatedly
        /// The main thread stopped responding and the watchdog switched the tap off.
        case mainThreadUnresponsive
    }

    private(set) var status: Status = .stopped {
        didSet {
            if status != oldValue { log("Status: \(oldValue) → \(status)") }
        }
    }
    private(set) var logLines: [String] = []

    /// HomeRower stopped itself to protect keyboard input more than a couple of times in
    /// a row, so it won't restart on its own. The permission screen offers Try Again.
    private(set) var needsManualRetry = false

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
    /// While running, checks that access is still on and that the tap still works.
    @ObservationIgnored private var accessMonitor: Task<Void, Never>?
    /// Switches the tap off from a background thread if the main thread hangs.
    @ObservationIgnored private let watchdog = TapWatchdog()
    /// Failed tap attempts in a row while access looked granted.
    @ObservationIgnored private var blockedAttempts = 0
    /// Fail-safe stops in a row (other than plain access loss), for backing off restarts.
    @ObservationIgnored private var consecutiveFailSafes = 0
    /// No automatic restart before this time (system uptime), after a fail-safe stop.
    @ObservationIgnored private var restartNotBefore: TimeInterval?
    /// When the current tap started (system uptime).
    @ObservationIgnored private var tapStartedAt: TimeInterval?
    /// Times the tap was re-enabled after macOS disabled it, for bounding retries.
    @ObservationIgnored private var tapReenableTimes: [TimeInterval] = []

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HomeRower", category: "EventTap")

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
    func requestPermission() {
        if neededPermission == .accessibility {
            requestAccessibility()
            return
        }
        // Input Monitoring: the first time, asking adds HomeRower to the list and macOS
        // shows its own alert with a button that opens the list, so the list isn't opened
        // here as well. macOS only shows that alert once, so after that this opens the list.
        let promptedKey = Self.promptedKey(for: neededPermission)
        guard UserDefaults.standard.bool(forKey: promptedKey) else {
            UserDefaults.standard.set(true, forKey: promptedKey)
            _ = CGRequestListenEventAccess()
            return
        }
        openPrivacySettings(neededPermission)
    }

    /// Always asks macOS, because only asking adds HomeRower back to the list after its
    /// entry was deleted (if the entry exists, asking does no harm). macOS sometimes answers
    /// with its own alert, whose button opens the list; if it doesn't, the list is opened
    /// here instead, so the user never gets the alert and the list at the same time.
    private func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Task { [weak self] in
            // The alert takes a moment to appear; look for it for up to a second.
            for _ in 0..<7 {
                try? await Task.sleep(for: .milliseconds(150))
                if Self.isAccessibilityAlertShowing() {
                    self?.log("macOS showed its Accessibility alert; letting it open System Settings")
                    return
                }
            }
            self?.log("No Accessibility alert from macOS; opening System Settings")
            self?.openPrivacySettings(.accessibility)
        }
    }

    /// Whether macOS's "would like to control this Mac" alert is on screen. It comes from
    /// the `universalAccessAuthWarn` process. Window owner names are readable without
    /// Screen Recording access (window titles aren't, and aren't needed).
    private static func isAccessibilityAlertShowing() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        return windows.contains { window in
            (window[kCGWindowOwnerName as String] as? String)?
                .localizedCaseInsensitiveContains("universalAccessAuthWarn") == true
        }
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
        needsManualRetry = false
        restartNotBefore = nil
        consecutiveFailSafes = 0
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
            // Access being off now means the user is turning it back on, so the next
            // time it's on is a fresh start, not a retry of a failed tap.
            needsManualRetry = false
            restartNotBefore = nil
            return false
        }
        // After a fail-safe stop, don't put a tap back in front of the keyboard until
        // the back-off has passed, or at all once it has failed too often.
        if needsManualRetry { return false }
        if let restartNotBefore, ProcessInfo.processInfo.systemUptime < restartNotBefore { return false }

        if createTap() { return true }

        blockedAttempts += 1
        if !CGPreflightListenEventAccess() {
            neededPermission = .inputMonitoring
        } else if blockedAttempts >= 4 {
            isTapBlocked = true
        }
        return false
    }

    /// Starts again after HomeRower stopped itself too often to restart on its own.
    func retryAfterFailSafe() {
        log("Try Again pressed")
        needsManualRetry = false
        restartNotBefore = nil
        consecutiveFailSafes = 0
        if tryStart() {
            permissionWatcher?.cancel()
            permissionWatcher = nil
        } else {
            waitForPermission()
        }
    }

    /// Whether the access the running tap depends on is still on.
    ///
    /// These checks report what's in Privacy & Security, not whether the tap works: when
    /// HomeRower's entry is deleted, they can keep reporting access while macOS rejects
    /// its events. The echo check in `monitorTap()` covers that.
    private var hasRequiredAccess: Bool {
        guard AXIsProcessTrusted() else { return false }
        // Input Monitoring only matters if this Mac needed it to start the tap.
        return neededPermission != .inputMonitoring || CGPreflightListenEventAccess()
    }

    /// Permission and tap state in one line, for the log.
    private var diagnostics: String {
        let tapState = tap.map { CGEvent.tapIsEnabled(tap: $0) ? "enabled" : "disabled" } ?? "none"
        return "Accessibility=\(AXIsProcessTrusted()) PostEvent=\(CGPreflightPostEventAccess()) "
            + "InputMonitoring=\(CGPreflightListenEventAccess()) tap=\(tapState) status=\(status)"
    }

    /// While the tap runs, checks four times a second that it still works, and stops it
    /// (giving input back) as soon as anything looks wrong:
    /// - the watchdog switched it off because the main thread hung,
    /// - posted events stopped coming back (macOS is rejecting them),
    /// - macOS reports it disabled,
    /// - a permission check reports access is off.
    private func monitorTap() {
        accessMonitor?.cancel()
        accessMonitor = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, let tap = self.tap else { return }
                tick += 1
                let now = ProcessInfo.processInfo.systemUptime

                // Before the heartbeat, so a trip from a hang that just ended is seen.
                if self.watchdog.takeDidTrip() {
                    self.failSafeStop(.mainThreadUnresponsive, detectedBy: "watchdog")
                    return
                }
                self.watchdog.heartbeat()

                if let since = self.emitter.awaitingEchoSince, now - since > Self.echoTimeout {
                    self.failSafeStop(.postingBlocked, detectedBy: "echo check")
                    return
                }

                // The rest involves IPC to the system, so only once a second.
                guard tick % 4 == 0 else { continue }
                if !self.hasRequiredAccess {
                    self.failSafeStop(.accessRevoked, detectedBy: "access monitor")
                    return
                }
                // A disabled tap is handled by `handleTapDisabled`; if it stays disabled
                // with no notification, stop rather than leave a dead tap installed.
                if !CGEvent.tapIsEnabled(tap: tap), self.tapReenableTimes.isEmpty {
                    self.failSafeStop(.tapDisabledRepeatedly, detectedBy: "access monitor")
                    return
                }
                // Running fine for a while: earlier failures no longer count toward giving up.
                if let started = self.tapStartedAt, now - started > 60 {
                    self.consecutiveFailSafes = 0
                }
            }
        }
    }

    /// How long a posted event may take to come back before posting counts as blocked.
    private static let echoTimeout: TimeInterval = 0.5

    /// Gives keyboard input back first, then works out when to try again.
    ///
    /// The tap comes down before anything else, so input recovers even if the rest
    /// (logging, UI) goes wrong. Safe to call repeatedly.
    private func failSafeStop(_ reason: FailSafeReason, detectedBy source: String) {
        guard tap != nil else { return }
        let before = diagnostics
        teardownTap()
        log("Fail-safe stop (\(reason), detected by \(source)). Before: \(before)")

        // The entry may have been removed, not just switched off. macOS only adds it back
        // through its alert, so ask through the alert again next time.
        if reason == .accessRevoked || reason == .postingBlocked {
            for permission in [Permission.accessibility, .inputMonitoring] {
                UserDefaults.standard.removeObject(forKey: Self.promptedKey(for: permission))
            }
        }

        // Plain access loss waits for access to come back. Anything else means the checks
        // said yes but the tap didn't work, so back off, and after a couple of tries stop
        // trying until the user says so, rather than trap the keyboard again and again.
        if reason != .accessRevoked {
            consecutiveFailSafes += 1
            if consecutiveFailSafes > Self.restartDelays.count {
                needsManualRetry = true
                log("Not restarting on its own after \(consecutiveFailSafes) fail-safe stops; waiting for Try Again")
            } else {
                let delay = Self.restartDelays[consecutiveFailSafes - 1]
                restartNotBefore = ProcessInfo.processInfo.systemUptime + delay
                log("Will try again in \(Int(delay)) s if access looks on")
            }
        }
        waitForPermission()
    }

    /// Back-off before each automatic restart after a fail-safe stop.
    private static let restartDelays: [TimeInterval] = [3, 10]

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
        tapStartedAt = ProcessInfo.processInfo.systemUptime
        tapReenableTimes = []
        emitter.resetEchoTracking()
        watchdog.watch(tap)
        permissionWatcher?.cancel()
        permissionWatcher = nil
        isTapBlocked = false
        blockedAttempts = 0
        restartNotBefore = nil
        status = .running
        log("Event tap running. \(diagnostics)")
        monitorTap()
        return true
    }

    /// Stops the tap and every task around it.
    func stop() {
        permissionWatcher?.cancel()
        permissionWatcher = nil
        teardownTap()
        status = .stopped
    }

    /// Removes the tap so it can't intercept input any more, then releases any modifiers
    /// HomeRower is holding. Safe to call repeatedly, and never called from inside the
    /// tap callback.
    private func teardownTap() {
        accessMonitor?.cancel()
        accessMonitor = nil

        // Forget the tap first, so nothing (including the watchdog) can touch it again.
        let oldTap = tap
        let oldSource = runLoopSource
        tap = nil
        runLoopSource = nil
        tapStartedAt = nil
        tapReenableTimes = []
        watchdog.watch(nil)

        if let oldTap {
            CGEvent.tapEnable(tap: oldTap, enable: false)
        }
        if let oldSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), oldSource, .commonModes)
        }
        if let oldTap {
            CFMachPortInvalidate(oldTap)
        }

        // With the tap gone, input flows normally; now drop engine state and release any
        // synthetic modifiers so nothing is left held down.
        resetEngine()
        emitter.resetEchoTracking()
    }

    /// macOS disabled the tap. A timeout (the callback was too slow) can be recovered
    /// from a few times; anything else, or a tap that keeps getting disabled, is a sign
    /// macOS doesn't want it, so it comes down instead of being forced back on.
    private func handleTapDisabled(byTimeout: Bool) {
        guard status == .running, let tap else { return }
        let kind = byTimeout ? "timeout" : "user input"
        log("macOS disabled the tap (\(kind)). \(diagnostics)")

        if watchdog.takeDidTrip() {
            failSafeStop(.mainThreadUnresponsive, detectedBy: "watchdog")
            return
        }
        guard hasRequiredAccess else {
            failSafeStop(.accessRevoked, detectedBy: "tap disabled (\(kind))")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        tapReenableTimes.removeAll { now - $0 > Self.reenableWindow }
        // Timeouts get a few retries per window; a disable for user input only one.
        let limit = byTimeout ? Self.maxTimeoutReenables : 1
        guard tapReenableTimes.count < limit else {
            failSafeStop(.tapDisabledRepeatedly, detectedBy: "tap disabled (\(kind))")
            return
        }

        tapReenableTimes.append(now)
        // Events posted while the tap was off never come back; don't count them.
        emitter.resetEchoTracking()
        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        log("Re-enabled the tap (\(tapReenableTimes.count) of \(limit) in \(Int(Self.reenableWindow)) s); enabled=\(isEnabled)")
        if !isEnabled {
            failSafeStop(.tapDisabledRepeatedly, detectedBy: "re-enable failed")
        }
    }

    /// How far back re-enables count toward the limit.
    private static let reenableWindow: TimeInterval = 30
    /// Re-enables allowed after timeouts within `reenableWindow`.
    private static let maxTimeoutReenables = 3

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
            // The tap is off now, so input already passes through. Decide what to do after
            // this callback returns: the decision involves permission IPC and may tear the
            // tap down, neither of which belongs inside the callback.
            let byTimeout = type == .tapDisabledByTimeout
            Task { [weak self] in self?.handleTapDisabled(byTimeout: byTimeout) }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        // Our own posted events come back through the tap: leave them alone. Their coming
        // back also shows that macOS is still accepting them.
        if event.getIntegerValueField(.eventSourceUserData) == Config.syntheticEventTag {
            emitter.noteEcho()
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
            ), isKeyEvent: true)
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
                if logsKeyEvents { log("\(down ? "Hold" : "Release") \(modifier.rawValue)", isKeyEvent: true) }
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

    /// Adds a line to the in-app log. Lifecycle messages also go to the system log
    /// (`log show --predicate 'subsystem == "<bundle ID>"'`), so they survive a forced
    /// restart. Key events never do: `isKeyEvent` keeps typing out of the system log.
    private func log(_ message: String, isKeyEvent: Bool = false) {
        if !isKeyEvent {
            Self.logger.notice("\(message, privacy: .public)")
        }
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
