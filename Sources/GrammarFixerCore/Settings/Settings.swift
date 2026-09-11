import Foundation

/// Настройки круга. Читаются заново на каждом обращении, чтобы переключатель
/// из меню действовал сразу и без перезапуска.
///
/// Хранилище — UserDefaults, поэтому то же самое переключается из терминала:
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

    /// Полным восстановление не бывает: обещанные и отложенные типы буфера
    /// глубокой копии не поддаются, у них ещё нет данных. Поэтому выключатель
    /// и существует — как честный запасной выход, а не как причуда.
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
