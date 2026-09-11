import Foundation

/// Нештатные исходы круга. Каждый из них раньше был тихим сбоем, поэтому у
/// каждого есть текст для человека. Текст английский: весь интерфейс на
/// английском, за этим следит тест.
public enum RoundTripError: String, CaseIterable, Equatable, Sendable, Error {
    case accessibilityDenied
    case secureInputActive
    case unsupportedSelection
    case focusLost
    case unknownTargetApp
    case hotKeyUnavailable

    public var title: String {
        switch self {
        case .accessibilityDenied: "Accessibility access is off"
        case .secureInputActive: "Secure input is active"
        case .unsupportedSelection: "Nothing to fix"
        case .focusLost: "The target app did not come back"
        case .unknownTargetApp: "No app to paste into"
        case .hotKeyUnavailable: "The shortcut is taken"
        }
    }

    public var message: String {
        switch self {
        case .accessibilityDenied:
            "GrammarFixer cannot read or replace your selection until you grant it in System Settings."
        case .secureInputActive:
            "Another app has turned on secure input, so keystrokes cannot be delivered. "
                + "Leave the password field or terminal that started it and try again."
        case .unsupportedSelection:
            "Whatever was selected did not come through as text. Select some text and try again."
        case .focusLost:
            "Nothing was pasted, so the text did not end up in the wrong window. Try again."
        case .unknownTargetApp:
            "GrammarFixer could not tell which app the text came from, so it pasted nothing."
        case .hotKeyUnavailable:
            "Another app already owns ⇧⌃⌥⌘G, so GrammarFixer never hears it. "
                + "Free the shortcut in that app, then restart GrammarFixer."
        }
    }
}
