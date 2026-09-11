import Foundation

/// The round trip's settings. Read afresh on every access so that a switch in
/// the menu takes effect at once and without a restart.
///
/// The store is UserDefaults, so the same switches work from a terminal:
///
///     defaults write com.badta5te.GrammarFixer RestoreClipboardAfterPaste -bool false
@MainActor
public final class Settings {
    public static let restoreClipboardKey = "RestoreClipboardAfterPaste"
    public static let pasteMethodKey = "PasteMethod"
    public static let writesLogKey = "WriteLog"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.restoreClipboardKey: true,
            Self.pasteMethodKey: PasteMethod.clipboard.rawValue,
            Self.writesLogKey: true,
        ])
    }

    /// Restoring is never complete: promised and lazy clipboard types cannot
    /// be deep-copied because they have no data yet. That is why the switch
    /// exists, as an honest way out rather than a quirk.
    public var restoreClipboardAfterPaste: Bool {
        get { defaults.bool(forKey: Self.restoreClipboardKey) }
        set { defaults.set(newValue, forKey: Self.restoreClipboardKey) }
    }

    public var pasteMethod: PasteMethod {
        get { PasteMethod(rawValue: defaults.string(forKey: Self.pasteMethodKey) ?? "") ?? .clipboard }
        set { defaults.set(newValue.rawValue, forKey: Self.pasteMethodKey) }
    }

    public var writesLog: Bool {
        get { defaults.bool(forKey: Self.writesLogKey) }
        set { defaults.set(newValue, forKey: Self.writesLogKey) }
    }
}
