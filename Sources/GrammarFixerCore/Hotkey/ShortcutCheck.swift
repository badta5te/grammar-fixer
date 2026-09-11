import Foundation

/// Why a combination cannot be had.
///
/// Three different refusals, and the difference matters to the person: one is
/// about the combination itself, one is the system's, and one is another app's.
public enum ShortcutRefusal: String, CaseIterable, Equatable, Sendable {
    /// Nothing but a letter, or a letter with shift: typing, not a shortcut.
    case noModifiers
    /// macOS uses it for something of its own.
    case takenByTheSystem
    /// Carbon would not register it, which means another app holds it.
    case refusedByTheSystem

    public func notice(for shortcut: Shortcut) -> Notice {
        switch self {
        case .noModifiers:
            Notice(
                title: "\(shortcut.display) would fire while you type",
                message: "A global shortcut needs ⌘, ⌃ or ⌥ in it. Shift on its own is a capital letter."
            )
        case .takenByTheSystem:
            Notice(
                title: "macOS already uses \(shortcut.display)",
                message: "Pick another combination, or free this one under "
                    + "System Settings → Keyboard → Keyboard Shortcuts."
            )
        case .refusedByTheSystem:
            Notice(
                title: "\(shortcut.display) is already taken",
                message: "Another app owns it, so \(AppInfo.name) never hears the press. "
                    + "Free it in that app, or pick another combination."
            )
        }
    }
}

/// Whether a combination can be taken, asked before anything is registered.
public enum ShortcutCheck {
    @MainActor
    public static func run(
        _ shortcut: Shortcut,
        takenBy system: Set<Shortcut> = SystemShortcuts.current
    ) -> ShortcutRefusal? {
        guard !shortcut.modifiers.isDisjoint(with: .real) else { return .noModifiers }
        guard !system.contains(shortcut) else { return .takenByTheSystem }
        return nil
    }
}
