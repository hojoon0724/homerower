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
        didSet { store.opensSettingsAtLaunch = opensSettingsAtLaunch }
    }

    /// The launch-time window decision has been made, so it isn't made again.
    @ObservationIgnored var didHandleLaunch = false

    @ObservationIgnored private let store: SettingsStore
    private static let logger = Logger.homeRower(category: "LaunchSettings")

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        opensSettingsAtLaunch = store.opensSettingsAtLaunch

        // Launch at login is on by default. Turn it on once, on first launch; after that,
        // the user's choice (here or in System Settings) is left alone.
        // (Not in Xcode previews, which would add the preview host to Login Items.)
        if !AppEnvironment.isPreview, !store.didApplyLaunchAtLoginDefault {
            store.didApplyLaunchAtLoginDefault = true
            register()
        }
        refresh()
    }

    /// Launch settings for SwiftUI previews. The launch-time window decision counts as
    /// made, so a preview never opens windows.
    static func preview() -> LaunchSettings {
        let settings = LaunchSettings(store: .preview)
        settings.didHandleLaunch = true
        return settings
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
