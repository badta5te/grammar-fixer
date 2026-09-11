import AppKit

/// Light, dark, or whatever the system is doing.
///
/// Worth a setting rather than following the system alone: this app's windows
/// appear over somebody else's and stay for seconds. A permanently light panel
/// over a dark editor is unpleasant at night, and the reverse is what somebody
/// who keeps the system dark but wants to read text on white is after.
public enum Theme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means the app states no preference, which is how AppKit is told
    /// to follow the system.
    public var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Applied to the application rather than to each window, so windows that
    /// are already open change with it instead of keeping the old theme until
    /// they are closed and opened again.
    @MainActor
    public func apply() {
        NSApp?.appearance = appearance
    }
}
