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

    /// Accessibility is on, but the tap still can't be created: a stale entry (e.g. after
    /// re-signing) or a denied PostEvent entry. Removing and re-adding HomeRower fixes both.
    private(set) var isTapBlocked = false

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
            store.tappingTermMs = tappingTermMs
            engine.settings.tappingTerm = tappingTermMs / 1000
        }
    }

    /// Typing-speed rule: tap if pressed within this many milliseconds of the last key (0 = off).
    var priorIdleMs: Double {
        didSet {
            store.priorIdleMs = priorIdleMs
            engine.settings.priorIdle = priorIdleMs / 1000
        }
    }

    /// The layout in use. Change it with `setModifier`, `setCapsLockTarget` or `select`,
    /// which keep the system's Caps Lock mapping in step.
    private(set) var layout: Layout {
        didSet {
            store.layout = layout
            engine.settings.keyMap = Self.engineKeyMap(for: layout)
        }
    }

    /// Layouts the user saved by name.
    private(set) var savedLayouts: [SavedLayout] {
        didSet { store.savedLayouts = savedLayouts }
    }

    /// Which Layout menu entry is in use.
    private(set) var layoutSelection: LayoutSelection {
        didSet { store.layoutSelection = layoutSelection }
    }

    /// The assembly area for unsaved edits. The first edit to any layout copies it here
    /// with the change, and further edits go here too. It stays while another layout is
    /// in use, and goes away once saved or discarded. `nil` when there's nothing unsaved.
    private(set) var customLayout: Layout? {
        didSet { store.customLayout = customLayout }
    }

    /// The layout Custom was started from, to go back to if it's discarded while in use.
    private(set) var customBase: LayoutSelection? {
        didSet { store.customBase = customBase }
    }

    /// The user's own Default, or `nil` for the built-in one.
    private(set) var defaultOverride: Layout? {
        didSet { store.defaultLayout = defaultOverride }
    }

    /// An edit that would replace Custom, waiting for the user to decide
    /// (`confirmPendingEdit`, `cancelPendingEdit` or `saveCustomLayout`).
    private(set) var pendingEdit: LayoutEdit?

    /// The Default layout: the user's own if they saved one, otherwise the built-in one.
    var defaultLayout: Layout { defaultOverride ?? .default }

    /// Physical key → modifier it produces when held.
    var keyMap: [UInt16: ModifierSet] { layout.homeRowMods }

    /// The key Caps Lock acts as, or `nil` for normal Caps Lock.
    var capsLockTarget: UInt16? { layout.capsLockTarget }

    /// Physical keys currently down, for the keyboard view. Only tracked while the tap runs.
    private(set) var pressedKeys: Set<UInt16> = []

    /// Home-row keys currently held as their modifier, for the keyboard view.
    private(set) var heldKeys: Set<UInt16> = []

    /// While the UI is recording a key, every event passes through untouched.
    @ObservationIgnored var isRecordingKey = false

    @ObservationIgnored private let store: SettingsStore
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

    private static let logger = Logger.homeRower(category: "EventTap")
    private static let maxLogLines = 500

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        tappingTermMs = store.tappingTermMs
        priorIdleMs = store.priorIdleMs
        let layout = store.layout
        let savedLayouts = store.savedLayouts
        let defaultOverride = store.defaultLayout
        var customLayout = store.customLayout
        // Older versions didn't save the selection: work it out from the layout.
        var selection = store.layoutSelection ?? {
            if layout == .none { return .preset(.none) }
            if layout == (defaultOverride ?? .default) { return .preset(.default) }
            if let saved = savedLayouts.first(where: { $0.layout == layout }) { return .saved(saved.id) }
            return .custom
        }()
        if case .saved(let id) = selection, !savedLayouts.contains(where: { $0.id == id }) {
            selection = .custom
        }
        if selection == .custom, customLayout == nil {
            customLayout = layout
        }
        self.layout = layout
        self.savedLayouts = savedLayouts
        self.defaultOverride = defaultOverride
        self.customLayout = customLayout
        self.customBase = customLayout == nil ? nil : store.customBase
        self.layoutSelection = selection
        engine.settings = HoldTapEngine.Settings(
            tappingTerm: tappingTermMs / 1000,
            priorIdle: priorIdleMs / 1000,
            keyMap: Self.engineKeyMap(for: layout)
        )
    }

    /// The layout's hold modifiers as the engine sees keys: Caps Lock with hold modifiers
    /// arrives as its stand-in key.
    private static func engineKeyMap(for layout: Layout) -> [UInt16: ModifierSet] {
        var keyMap = layout.homeRowMods
        if let capsLock = keyMap.removeValue(forKey: KeyCode.capsLock) {
            keyMap[Config.capsLockStandIn] = capsLock
        }
        return keyMap
    }

    /// The event is Caps Lock, remapped to its stand-in because it has hold modifiers.
    private func isCapsLockStandIn(_ keyCode: UInt16) -> Bool {
        keyCode == Config.capsLockStandIn && !layout.capsLockModifiers.isEmpty
    }

    func resetTimingsToDefaults() {
        tappingTermMs = Config.tappingTerm * 1000
        priorIdleMs = Config.priorIdle * 1000
    }

    /// Sets the modifiers a physical key holds down; none makes it type normally.
    func setModifiers(_ modifiers: ModifierSet, for keyCode: UInt16) {
        edit(.modifier(modifiers, keyCode: keyCode))
    }

    /// Makes Caps Lock act as another key, or restores it with `nil`.
    /// Returns `false` if the mapping couldn't be applied.
    @discardableResult
    func setCapsLockTarget(_ keyCode: UInt16?) -> Bool {
        edit(.capsLockTarget(keyCode == KeyCode.capsLock ? nil : keyCode))
    }

    /// Gives Caps Lock hold modifiers (a tap still toggles Caps Lock), or none to make it
    /// normal again. Returns `false` if the mapping couldn't be applied.
    @discardableResult
    func setCapsLockModifiers(_ modifiers: ModifierSet) -> Bool {
        edit(.capsLockModifiers(modifiers))
    }

    /// The name of a Layout menu entry.
    func name(of selection: LayoutSelection) -> String {
        switch selection {
        case .preset(let preset): preset.displayName
        case .saved(let id): savedLayouts.first { $0.id == id }?.name ?? "Custom"
        case .custom: "Custom"
        }
    }

    // MARK: - Choosing layouts

    /// Switches to a preset, a saved layout or Custom. Switching never changes Custom.
    func select(_ selection: LayoutSelection) {
        guard let newLayout = layout(for: selection) else { return }
        apply(newLayout)
        layoutSelection = selection
    }

    private func layout(for selection: LayoutSelection) -> Layout? {
        switch selection {
        // Spelled out: a bare `.none` here would mean `nil`.
        case .preset(.none): Layout.none
        case .preset(.default): defaultLayout
        case .saved(let id): savedLayouts.first { $0.id == id }?.layout
        case .custom: customLayout
        }
    }

    /// Switches to a whole layout: hold modifiers, Caps Lock and layers.
    private func apply(_ newLayout: Layout) {
        if newLayout.capsLockSystemTarget != layout.capsLockSystemTarget {
            applyCapsLockRemap(newLayout.capsLockSystemTarget)
        }
        layout = newLayout
    }

    // MARK: - Editing

    /// Changes the layout in use. The result is always Custom. If a different, unsaved
    /// Custom would be replaced, the edit waits in `pendingEdit` for the user instead.
    /// Returns `false` if the edit couldn't be applied.
    @discardableResult
    private func edit(_ edit: LayoutEdit) -> Bool {
        guard edit.applied(to: layout) != layout else { return true }
        if layoutSelection != .custom, customLayout != nil {
            pendingEdit = edit
            return true
        }
        return commit(edit)
    }

    /// Applies an edit to the layout in use and makes the result Custom.
    @discardableResult
    private func commit(_ edit: LayoutEdit) -> Bool {
        let newLayout = edit.applied(to: layout)
        if newLayout.capsLockSystemTarget != layout.capsLockSystemTarget {
            guard applyCapsLockRemap(newLayout.capsLockSystemTarget) else { return false }
        }
        if layoutSelection != .custom {
            customBase = layoutSelection
        }
        layout = newLayout
        customLayout = newLayout
        layoutSelection = .custom
        return true
    }

    /// Replace: the pending edit goes ahead and replaces Custom.
    func confirmPendingEdit() {
        guard let pendingEdit else { return }
        self.pendingEdit = nil
        commit(pendingEdit)
    }

    /// Cancel: the pending edit is dropped and nothing changes.
    func cancelPendingEdit() {
        pendingEdit = nil
    }

    // MARK: - Saving

    /// Whether a new layout can be saved under this name.
    func isNameAvailable(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = LayoutPreset.reservedNames + savedLayouts.map(\.name)
        return !name.isEmpty && !taken.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Save Layout…: saves the layout in use and switches to the saved copy. Saving
    /// Custom uses it up, so Custom goes away.
    func saveCurrentLayout(as target: LayoutSaveTarget) {
        let wasCustom = layoutSelection == .custom
        guard let saved = save(layout, as: target) else { return }
        layoutSelection = saved
        if wasCustom {
            clearCustom()
        }
    }

    /// Save Custom… from the replace alert: saves Custom, then lets the pending edit
    /// start a new Custom.
    func saveCustomLayout(as target: LayoutSaveTarget) {
        guard let customLayout, let saved = save(customLayout, as: target) else { return }
        clearCustom()
        // Saved over the layout in use: switch to its new keys before the edit.
        if saved == layoutSelection, let updated = layout(for: saved) {
            apply(updated)
        }
        confirmPendingEdit()
    }

    /// Stores a layout and returns the menu entry it's now under.
    private func save(_ layoutToSave: Layout, as target: LayoutSaveTarget) -> LayoutSelection? {
        switch target {
        case .newLayout(let name):
            guard isNameAvailable(name) else { return nil }
            let saved = SavedLayout(name: name.trimmingCharacters(in: .whitespacesAndNewlines), layout: layoutToSave)
            savedLayouts.append(saved)
            return .saved(saved.id)
        case .default:
            defaultOverride = layoutToSave == .default ? nil : layoutToSave
            return .preset(.default)
        case .saved(let id):
            guard let index = savedLayouts.firstIndex(where: { $0.id == id }) else { return nil }
            savedLayouts[index].layout = layoutToSave
            return .saved(id)
        }
    }

    // MARK: - Managing

    /// Deletes a saved layout. If it's in use, Default takes over.
    func deleteLayout(id: SavedLayout.ID) {
        let wasInUse = layoutSelection == .saved(id)
        savedLayouts.removeAll { $0.id == id }
        if customBase == .saved(id) { customBase = nil }
        if wasInUse { select(.preset(.default)) }
    }

    /// Throws away Custom. If it's in use, the layout it started from takes over.
    func discardCustomLayout() {
        if layoutSelection == .custom {
            let base = customBase.flatMap { layout(for: $0) == nil ? nil : $0 } ?? .preset(.default)
            select(base)
        }
        clearCustom()
    }

    /// Brings back the built-in Default.
    func restoreDefaultLayout() {
        defaultOverride = nil
        if layoutSelection == .preset(.default) { apply(defaultLayout) }
    }

    private func clearCustom() {
        customLayout = nil
        customBase = nil
    }

    // MARK: - Caps Lock

    /// Tells the system to map Caps Lock to `target` (or back to itself) and logs the result.
    @discardableResult
    private func applyCapsLockRemap(_ target: UInt16?) -> Bool {
        guard CapsLockRemap.apply(target: target) else {
            log("Failed to remap Caps Lock")
            return false
        }
        switch target {
        case nil: log("Caps Lock restored")
        case Config.capsLockStandIn?: log("Caps Lock now has hold modifiers")
        case let target?: log("Caps Lock now acts as \(KeyNames.name(for: target))")
        }
        return true
    }

    /// Re-applies the saved Caps Lock mapping (called at launch).
    func applyKeyRemapping() {
        guard let target = layout.capsLockSystemTarget else { return }
        if !CapsLockRemap.apply(target: target) {
            log("Failed to remap Caps Lock")
        }
    }

    /// Removes the Caps Lock mapping from the system without forgetting it (called at quit).
    func clearKeyRemapping() {
        guard layout.capsLockSystemTarget != nil else { return }
        CapsLockRemap.apply(target: nil)
    }

    // MARK: - Lifecycle

    func start() {
        // A preview's buttons must not put a real tap in front of the keyboard.
        guard tap == nil, !AppEnvironment.isPreview else { return }
        if !tryStart() {
            log("Waiting for Accessibility access…")
            waitForPermission()
        }
    }

    // MARK: - Permissions

    private func tryStart() -> Bool {
        guard PrivacyAccess.isAccessibilityOn else {
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
        if blockedAttempts == 1 {
            log("macOS refused the tap. \(diagnostics)")
        }
        if blockedAttempts >= 4 {
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
        PrivacyAccess.isAccessibilityOn
    }

    /// Permission and tap state in one line, for the log.
    private var diagnostics: String {
        let tapState = tap.map { CGEvent.tapIsEnabled(tap: $0) ? "enabled" : "disabled" } ?? "none"
        return "\(PrivacyAccess.diagnostics) tap=\(tapState) status=\(status)"
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
        // synthetic modifiers so nothing is left held down. Key releases won't be seen
        // any more, so forget what's pressed.
        resetEngine()
        emitter.resetEchoTracking()
        if !pressedKeys.isEmpty { pressedKeys = [] }
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

    // MARK: - Log

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

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged {
            if let isDown = Self.isModifierKeyDown(keyCode, flags: event.flags) {
                notePhysicalKey(keyCode, isDown: isDown)
            }
            emitter.hardwareFlags = event.flags
            emitter.applyFlags(to: event)
            return Unmanaged.passUnretained(event)
        }

        let isCapsLock = isCapsLockStandIn(keyCode)
        if type == .keyDown || type == .keyUp {
            notePhysicalKey(isCapsLock ? KeyCode.capsLock : keyCode, isDown: type == .keyDown)
        }

        // Apps must never see the stand-in key. While the engine is off, Caps Lock is
        // plain Caps Lock: a press toggles it.
        if isCapsLock, !isEnabled || isRecordingKey {
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                CapsLockRemap.toggleCapsLock()
            }
            return nil
        }

        guard isEnabled, !isRecordingKey, type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyEvent = KeyEvent(
            keyCode: keyCode,
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
        if perform(actions), !isCapsLock {
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
            case let .key(keyCode, down, isRepeat) where isCapsLockStandIn(keyCode):
                // Caps Lock was tapped, not held: toggle it, as the key normally would.
                if down && !isRepeat { CapsLockRemap.toggleCapsLock() }
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
        updateHeldKeys()
        return passThrough
    }

    // MARK: - Key state for the keyboard view

    // Observers are notified on every assignment, so these only assign on a real change.

    private func notePhysicalKey(_ keyCode: UInt16, isDown: Bool) {
        if isDown != pressedKeys.contains(keyCode) {
            if isDown { pressedKeys.insert(keyCode) } else { pressedKeys.remove(keyCode) }
        }
    }

    private func updateHeldKeys() {
        var held = engine.heldKeys
        if held.remove(Config.capsLockStandIn) != nil, !layout.capsLockModifiers.isEmpty {
            held.insert(KeyCode.capsLock)
        }
        if held != heldKeys { heldKeys = held }
    }

    /// Whether a physical modifier key is down, from its `flagsChanged` event; `nil` for
    /// keys this can't tell (Caps Lock toggles instead).
    private static func isModifierKeyDown(_ keyCode: UInt16, flags: CGEventFlags) -> Bool? {
        if keyCode == KeyCode.function { return flags.contains(.maskSecondaryFn) }
        guard let modifier = Modifier.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        // The device-dependent bit tells left from right.
        let deviceBit = modifier.flags.subtracting([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        return flags.contains(deviceBit)
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

// MARK: - Previews

extension EventTap {
    /// An event tap in a given state, for SwiftUI previews. It never creates a real tap,
    /// and its settings are saved apart from the app's.
    static func preview(
        status: Status = .running,
        isEnabled: Bool = true,
        needsManualRetry: Bool = false,
        isTapBlocked: Bool = false,
        capsLockTarget: UInt16? = nil,
        capsLockModifiers: ModifierSet = [],
        logLines: [String] = []
    ) -> EventTap {
        let eventTap = EventTap(store: .preview)
        eventTap.status = status
        eventTap.isEnabled = isEnabled
        eventTap.needsManualRetry = needsManualRetry
        eventTap.isTapBlocked = isTapBlocked
        eventTap.layout.capsLockTarget = capsLockTarget
        eventTap.layout.homeRowMods[KeyCode.capsLock] = capsLockModifiers.isEmpty ? nil : capsLockModifiers
        // Set last: the changes above add their own log lines.
        eventTap.logLines = logLines
        return eventTap
    }

    /// An event tap with a given set of layouts, for previewing the layout sheets. Preview
    /// settings persist between runs, so every layout setting is set here, not inherited.
    static func previewWithLayouts(
        savedLayouts: Bool = true,
        modifiedDefault: Bool = true,
        custom: Bool = true
    ) -> EventTap {
        let eventTap = preview()
        var noPinkies = Layout.default
        noPinkies.homeRowMods[KeyCode.a] = nil
        noPinkies.homeRowMods[KeyCode.semicolon] = nil
        var escCapsLock = Layout.default
        escCapsLock.capsLockTarget = KeyCode.escape

        eventTap.savedLayouts = savedLayouts
            ? [SavedLayout(name: "user001", layout: noPinkies), SavedLayout(name: "Gaming", layout: .none)]
            : []
        eventTap.defaultOverride = modifiedDefault ? escCapsLock : nil
        eventTap.customLayout = custom ? escCapsLock.applyingPreviewEdit() : nil
        eventTap.customBase = custom ? .preset(.default) : nil
        eventTap.layoutSelection = custom ? .custom : .preset(.default)
        eventTap.layout = eventTap.customLayout ?? eventTap.defaultLayout
        eventTap.pendingEdit = nil
        return eventTap
    }
}

private extension Layout {
    /// A small change, standing in for the user's unsaved edits in previews.
    func applyingPreviewEdit() -> Layout {
        LayoutEdit.modifier(.leftCommand, keyCode: KeyCode.g).applied(to: self)
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
