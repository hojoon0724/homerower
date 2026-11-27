import SwiftUI

@main struct HomeRowerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("HomeRower", id: "main") {
            RootView(eventTap: appDelegate.eventTap)
        }
        .defaultLaunchBehavior(.presented)
        // The window's size follows MainView's frame: fixed width, flexible height.
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContentView(eventTap: appDelegate.eventTap)
        } label: {
            MenuBarLabel(eventTap: appDelegate.eventTap)
        }

        Window("HomeRower Log", id: "log") {
            LogView(eventTap: appDelegate.eventTap)
        }
        .defaultSize(width: 420, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// The main window's content: the permission screen until HomeRower is running,
/// then the settings.
struct RootView: View {
    let eventTap: EventTap

    var body: some View {
        Group {
            switch eventTap.status {
            case .running:
                MainView(eventTap: eventTap)
            case .waitingForPermission:
                PermissionView(eventTap: eventTap)
            case .stopped:
                // Only for the moment before the launch check finishes.
                ProgressView()
                    .frame(width: 480, height: 300)
            }
        }
        .animation(.default, value: eventTap.status)
        // Show a Dock icon only while this window is open.
        .onAppear {
            guard !Self.isPreview else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            guard !Self.isPreview else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Don't touch the Dock icon of the Xcode preview host.
    private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

/// The menu bar icon. It's the one view that always exists, even with every window
/// closed, so it also brings up the permission screen if access is turned off.
struct MenuBarLabel: View {
    let eventTap: EventTap
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "oar.2.crossed")
            .accessibilityLabel("HomeRower")
            .onChange(of: eventTap.status) { oldStatus, newStatus in
                // Running → waiting means access was turned off or removed. (Stopped →
                // waiting is the same thing seen mid-way, or the launch check.)
                guard oldStatus != newStatus, newStatus == .waitingForPermission else { return }
                showPermissionScreen()
            }
    }

    /// Opens the main window (it shows the permission screen) in front of everything.
    private func showPermissionScreen() {
        openWindow(id: "main")
        NSApp.activate()
        // SwiftUI names the window after the scene ID, with a suffix.
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventTap = EventTap()

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
