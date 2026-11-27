import AppKit
import CoreGraphics
import Observation

/// Owns the CGEventTap and connects it to the engine and the emitter.
@Observable
final class EventTap {
    enum Status: Equatable {
        case stopped
        case waitingForPermission
        case running
    }

    private(set) var status: Status = .stopped
    private(set) var logLines: [String] = []

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

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var engine = HoldTapEngine()
    @ObservationIgnored private let emitter = Emitter()

    private static let maxLogLines = 500

    // MARK: - Lifecycle

    func start() {
        guard tap == nil else { return }

        // Prompts the first time; the tap can't be created until both are granted.
        let canListen = CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        let canPost = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        guard canListen, canPost else {
            status = .waitingForPermission
            log("Missing permission (listen: \(canListen), post: \(canPost)). Grant Input Monitoring and Accessibility, then Retry.")
            return
        }

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
            status = .waitingForPermission
            log("Failed to create the event tap. Check Privacy & Security settings, then Retry.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        status = .running
        log("Event tap running")
    }

    func stop() {
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

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
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

        guard isEnabled, type == .keyDown || type == .keyUp else {
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
