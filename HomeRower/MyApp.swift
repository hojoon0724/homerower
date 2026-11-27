import SwiftUI

@main struct HomeRowerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("HomeRower", systemImage: "keyboard") {
            MenuContentView(eventTap: appDelegate.eventTap)
        }

        Window("HomeRower Log", id: "log") {
            LogView(eventTap: appDelegate.eventTap)
        }
        .defaultSize(width: 420, height: 480)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventTap = EventTap()

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventTap.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Make sure no synthetic modifier is left stuck down.
        eventTap.stop()
    }
}
