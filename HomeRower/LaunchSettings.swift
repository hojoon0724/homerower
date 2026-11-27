import Foundation
import Observation
import ServiceManagement
import os

/// Whether HomeRower starts at login, and whether its settings window opens when it launches.
@Observable
final class LaunchSettings {
    /// HomeRower is in the system's Login Items. That list is the source of truth, so
    /// switching HomeRower off in System Settings → General → Login Items shows here too.
    private(set) var launchesAtLogin = false

    /// macOS needs the user to allow HomeRower in Login Items before it starts at login.
    private(set) var loginItemNeedsApproval = false

    /// Open the settings window when HomeRower launches. Off by default: HomeRower lives in
    /// the menu bar. (The window still opens when permission is missing.)
    var opensSettingsAtLaunch: Bool {
        didSet { UserDefaults.standard.set(opensSettingsAtLaunch, forKey: Self.opensSettingsKey) }
    }

    /// The launch-time window decision has been made, so it isn't made again.
    @ObservationIgnored var didHandleLaunch = false

    private static let opensSettingsKey = "opensSettingsAtLaunch"
    private static let didApplyLoginDefaultKey = "didApplyLaunchAtLoginDefault"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HomeRower", category: "LaunchSettings")

    init() {
        let defaults = UserDefaults.standard
        opensSettingsAtLaunch = defaults.bool(forKey: Self.opensSettingsKey)

        // Launch at login is on by default. Turn it on once, on first launch; after that,
        // the user's choice (here or in System Settings) is left alone.
        if !defaults.bool(forKey: Self.didApplyLoginDefaultKey) {
            defaults.set(true, forKey: Self.didApplyLoginDefaultKey)
            register()
        }
        refresh()
    }

    /// Adds HomeRower to Login Items, or removes it.
    func setLaunchesAtLogin(_ isOn: Bool) {
        if isOn {
            register()
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Self.logger.error("Couldn't remove HomeRower from Login Items: \(error.localizedDescription, privacy: .public)")
            }
        }
        refresh()
    }

    /// Re-reads the Login Items state, which the user can change in System Settings.
    func refresh() {
        let status = SMAppService.mainApp.status
        launchesAtLogin = status == .enabled
        loginItemNeedsApproval = status == .requiresApproval
    }

    /// Opens System Settings → General → Login Items.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func register() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            Self.logger.error("Couldn't add HomeRower to Login Items: \(error.localizedDescription, privacy: .public)")
        }
    }
}
