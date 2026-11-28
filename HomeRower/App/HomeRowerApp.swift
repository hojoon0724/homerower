import SwiftUI

@main struct HomeRowerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("HomeRower", id: AppWindow.main.rawValue) {
            RootView(eventTap: appDelegate.eventTap, launchSettings: appDelegate.launchSettings)
        }
        // The menu bar icon decides whether to open it at launch (see `MenuBarLabel`).
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        // The window's size follows MainView's frame: fixed width, flexible height.
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContentView(eventTap: appDelegate.eventTap)
        } label: {
            MenuBarLabel(eventTap: appDelegate.eventTap, launchSettings: appDelegate.launchSettings)
        }

        Window("HomeRower Log", id: AppWindow.log.rawValue) {
            LogView(eventTap: appDelegate.eventTap)
        }
        .defaultSize(width: 420, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

// Previews can't render scenes, so this shows the main window's content.
#Preview("App") {
    RootView(eventTap: .preview(), launchSettings: .preview())
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventTap = EventTap()
    let launchSettings = LaunchSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventTap.applyKeyRemapping()
        eventTap.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Make sure no synthetic modifier is left stuck down, and Caps Lock is normal again.
        eventTap.stop()
        eventTap.clearKeyRemapping()
    }
}
