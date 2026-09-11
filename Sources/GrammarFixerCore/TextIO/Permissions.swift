import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Accessibility access. It is needed for sending events, not for reading: a
/// Carbon hot key registers and fires without it, while synthetic ⌘C and ⌘V are
/// not delivered without it.
///
/// The state is asked again before every round rather than remembered at
/// launch: access can be revoked in System Settings, and then the round has to
/// lead to onboarding rather than to silence.
@MainActor
public enum Accessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks the system to show its own window offering to grant access. It
    /// appears only once per installation, so it cannot be relied on as the
    /// only way in.
    @discardableResult
    public static func requestAccess() -> Bool {
        // The constant kAXTrustedCheckOptionPrompt is declared in C as a
        // mutable variable, and Swift 6 refuses to touch it. Its value is
        // exactly this string.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    public static func openSystemSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

/// Secure input. While it is on, synthetic events are dropped silently, and
/// "nothing was selected" would be shown where text plainly is.
@MainActor
public enum SecureInput {
    public static var isActive: Bool { IsSecureEventInputEnabled() }
}
