import SwiftUI

/// Contents of the menu-bar menu.
struct MenuContentView: View {
    @Bindable var eventTap: EventTap
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Enabled", isOn: $eventTap.isEnabled)

        switch eventTap.status {
        case .running:
            EmptyView()
        case .waitingForPermission:
            Button("Set Up Permission…") {
                openWindow.bringToFront(.main)
            }
        case .stopped:
            Button("Start") {
                eventTap.start()
            }
        }

        Divider()

        Button("Open HomeRower…") {
            openWindow.bringToFront(.main)
        }
        Toggle("Log Key Events", isOn: $eventTap.logsKeyEvents)
        Button("Show Log") {
            openWindow.bringToFront(.log)
        }

        Divider()

        Button("Quit HomeRower") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// The real menu is drawn by the menu bar, which previews can't show (and opening a
// SwiftUI `Menu` crashes the preview). These styles make the items look like menu
// items instead of a window's buttons and checkboxes.

/// Width of the column on the left of a menu, where checkmarks go.
private let checkmarkColumnWidth: CGFloat = 20

private struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
    }
}

private struct MenuItemToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .overlay(alignment: .leading) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: checkmarkColumnWidth)
                    .offset(x: -checkmarkColumnWidth)
                    .opacity(configuration.isOn ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { configuration.isOn.toggle() }
    }
}

private func menuPreview(_ eventTap: EventTap) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        MenuContentView(eventTap: eventTap)
    }
    .buttonStyle(MenuItemButtonStyle())
    .toggleStyle(MenuItemToggleStyle())
    .padding(.leading, checkmarkColumnWidth + 8)
    .padding(.trailing, 14)
    .padding(.vertical, 6)
    .frame(width: 240)
    .background(.regularMaterial, in: .rect(cornerRadius: 10))
    .padding()
}

#Preview("Running") {
    menuPreview(.preview())
}

#Preview("Waiting for Permission") {
    menuPreview(.preview(status: .waitingForPermission))
}

#Preview("Stopped") {
    menuPreview(.preview(status: .stopped))
}
