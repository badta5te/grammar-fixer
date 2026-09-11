import AppKit
import SwiftUI

/// The access screen. It explains in words why the access is needed instead of
/// merely asking for it: Accessibility sounds like "read everything", and
/// somebody is entitled to understand what they are paying with.
///
/// The system shows its own offer only once per installation, so a button into
/// System Settings is mandatory.
@MainActor
public final class OnboardingPanel: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var pollTask: Task<Void, Never>?
    private let state = OnboardingState()

    public override init() { super.init() }

    public func show() {
        if let panel {
            panel.present()
            return
        }

        state.isTrusted = Accessibility.isTrusted
        let panel = FloatingPanel(styleMask: [.titled, .closable]) { [state] in
            OnboardingView(state: state)
        }
        panel.title = "\(AppInfo.name) setup"
        panel.delegate = self
        panel.present()
        self.panel = panel

        state.onOpenSettings = {
            // The system shows its own window once per installation and stays
            // quiet afterwards. We ask for it anyway: if it appears, the way
            // through is shorter.
            Accessibility.requestAccess()
            Accessibility.openSystemSettings()
        }
        state.onClose = { [weak self] in self?.dismiss() }

        // The system sends no notification when access is granted, so the
        // state is polled.
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let trusted = Accessibility.isTrusted
                if trusted != state.isTrusted {
                    state.isTrusted = trusted
                    Log.write("Accessibility access changed: \(trusted)")
                }
            }
        }
    }

    /// The close button in the title bar dismisses the window past our own
    /// buttons, and the polling would go on working into the void. Both paths
    /// share one cleanup, or they drift apart over time.
    public func windowWillClose(_ notification: Notification) {
        stopPolling()
        panel = nil
    }

    public func dismiss() {
        stopPolling()
        panel?.dismiss()
        panel = nil
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var isTrusted = false
    var onOpenSettings: () -> Void = {}
    var onClose: () -> Void = {}
}

private struct OnboardingView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(AppInfo.name) needs Accessibility access")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("It fixes the text you have selected, right where you are typing. "
                    + "To do that it presses ⌘C and ⌘V for you inside the app you are working in.")
                Text("macOS only lets an app send those keystrokes when you allow it under Accessibility. "
                    + "Reading is not the part that needs permission: without it nothing can be pasted back.")
                Text("\(AppInfo.name) never watches what you type. It touches your selection only when you press the shortcut.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            if state.isTrusted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("Select some text anywhere and press ⇧⌃⌥⌘G.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1.  Open System Settings below")
                    Text("2.  Find \(AppInfo.name) in the list")
                    Text("3.  Turn its switch on")
                }
                .font(.callout)

                Label("Waiting for access…", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !state.isTrusted {
                    Button("Open System Settings") { state.onOpenSettings() }
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
                Button(state.isTrusted ? "Done" : "Later") { state.onClose() }
                    .keyboardShortcut(state.isTrusted ? .defaultAction : .cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }
}
