import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Доступ Accessibility. Нужен именно для отправки событий: Carbon-хоткей
/// регистрируется и срабатывает без него, а вот синтетические ⌘C и ⌘V без
/// него не доставляются.
///
/// Состояние спрашивается заново перед каждым кругом, а не запоминается при
/// запуске: доступ можно отозвать в системных настройках, и тогда круг должен
/// привести к онбордингу, а не к тишине.
@MainActor
public enum Accessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Просит систему показать её собственное окно с предложением выдать
    /// доступ. Показывается только один раз за установку, поэтому на него
    /// нельзя полагаться как на единственный путь.
    @discardableResult
    public static func requestAccess() -> Bool {
        // Константа kAXTrustedCheckOptionPrompt объявлена в C изменяемой
        // переменной, и Swift 6 не даёт к ней обратиться. Значение у неё —
        // ровно эта строка.
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

/// Защищённый ввод. Пока он включён, синтетические события не доставляются
/// молча, и «ничего не выделено» показалось бы там, где текст выделен.
@MainActor
public enum SecureInput {
    public static var isActive: Bool { IsSecureEventInputEnabled() }
}
