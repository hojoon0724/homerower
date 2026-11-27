import AppKit
import CoreGraphics

/// A Privacy & Security setting the user has to turn on.
nonisolated enum Permission: CaseIterable, Equatable, Sendable {
    case accessibility
    case inputMonitoring

    /// The name System Settings uses for it.
    var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// The Privacy & Security pane that lists it.
    fileprivate var settingsPane: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
    }
}

/// Stateless helpers for checking and changing HomeRower's Privacy & Security entries.
enum PrivacyAccess {
    /// Opens the list for a permission in System Settings.
    static func openSettings(for permission: Permission) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether macOS's "would like to control this Mac" alert is on screen. It comes from
    /// the `universalAccessAuthWarn` process. Window owner names are readable without
    /// Screen Recording access (window titles aren't, and aren't needed).
    static func isAccessibilityAlertShowing() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        return windows.contains { window in
            (window[kCGWindowOwnerName as String] as? String)?
                .localizedCaseInsensitiveContains("universalAccessAuthWarn") == true
        }
    }

    /// Permission state in one line, for the log.
    static var diagnostics: String {
        "Accessibility=\(AXIsProcessTrusted()) PostEvent=\(CGPreflightPostEventAccess()) "
            + "InputMonitoring=\(CGPreflightListenEventAccess())"
    }

    /// The services `resetEntries(for:)` clears.
    static let tccServices = ["Accessibility", "PostEvent", "ListenEvent"]

    /// Runs `tccutil reset <service> <bundleID>` and returns its exit code (-1 if it couldn't run).
    nonisolated static func resetEntry(service: String, bundleID: String) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
}
