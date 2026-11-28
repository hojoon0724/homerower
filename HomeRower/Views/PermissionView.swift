import SwiftUI

/// Shown in the main window until HomeRower has the access it needs. Once access is
/// on, the tap starts by itself and the window switches to the settings.
struct PermissionView: View {
    let eventTap: EventTap

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow HomeRower to Use Your Keyboard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("HomeRower needs Accessibility access to read your key presses and send modifiers in their place.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Click **Open System Settings**.")
                step(2, "Drag HomeRower's icon below into the list, or click **+** and choose HomeRower.")
                step(3, "Turn on **HomeRower**. It starts on its own.")
            }

            AppIconDragSource()
                .frame(maxWidth: .infinity)

            statusRow

            HStack {
                Button("Quit HomeRower") {
                    NSApp.terminate(nil)
                }
                Spacer()
                openSettingsButton
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 480)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if eventTap.needsManualRetry {
            WarningBox(
                title: "HomeRower stopped to keep your keyboard working.",
                message: "macOS stopped accepting HomeRower's key events, which happens when HomeRower is removed from the list. Make sure HomeRower is in the list and turned on, then click Try Again."
            ) {
                HStack {
                    Button("Try Again") {
                        eventTap.retryAfterFailSafe()
                    }
                    openSettingsButton
                }
            }
        } else if eventTap.isTapBlocked {
            WarningBox(
                title: "HomeRower is turned on, but macOS isn't letting it start.",
                message: "HomeRower's entry in the list is out of date, which happens after HomeRower was rebuilt or moved. Select HomeRower in the list, click **−** to remove it, then add it again."
            ) {
                openSettingsButton
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for Accessibility access…")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var openSettingsButton: some View {
        Button("Open System Settings") {
            PrivacyAccess.openAccessibilitySettings()
        }
    }
}

private struct AppIconDragSource: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: PrivacyAccess.appIcon)
                .resizable()
                .frame(width: 56, height: 56)
                .onDrag { NSItemProvider(object: PrivacyAccess.appURL as NSURL) }
                .help("Drag into the Accessibility list")
                .accessibilityLabel("HomeRower app icon")
                .accessibilityHint("Drag into the Accessibility list in System Settings")
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([PrivacyAccess.appURL])
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }
}

/// An orange box explaining a problem, with buttons to fix it.
private struct WarningBox<Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Accessibility") {
    PermissionView(eventTap: .preview(status: .waitingForPermission))
}

#Preview("Stopped by Fail-Safe") {
    PermissionView(eventTap: .preview(status: .waitingForPermission, needsManualRetry: true))
}

#Preview("Tap Blocked") {
    PermissionView(eventTap: .preview(status: .waitingForPermission, isTapBlocked: true))
}

#Preview("Warning Box") {
    WarningBox(title: "Something went wrong.", message: "Well, this never happened before, I swear.") {
        HStack {
            HStack {
                Button("Ignore") {}
                Button("Report bug") {}
            }
            Spacer()
            HStack {
                Button("Quit") {}
            }
        }
    }
    .padding()
    .frame(width: 480)
}
