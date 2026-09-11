import AppKit
import Carbon.HIToolbox

/// Круг целиком: хоткей, захват, преобразование, вставка.
///
/// Каждая ветка выхода отсюда чем-то заканчивается — сигналом, сообщением или
/// онбордингом. Тихих отказов не остаётся ни одного: тихий отказ здесь значит,
/// что человек ждёт результата, которого не будет.
@MainActor
public final class RoundTripController {
    private let settings: Settings
    private let clipboard: Clipboard
    private let capture: TextCapture
    private let paster: TextPaster
    private let transform: TextTransforming
    private let notices: NoticePanel
    private let onAccessibilityDenied: () -> Void

    private var hotKey: HotKey?
    private var isRunning = false

    public init(
        settings: Settings,
        clipboard: Clipboard,
        capture: TextCapture,
        paster: TextPaster,
        transform: TextTransforming,
        notices: NoticePanel,
        onAccessibilityDenied: @escaping () -> Void
    ) {
        self.settings = settings
        self.clipboard = clipboard
        self.capture = capture
        self.paster = paster
        self.transform = transform
        self.notices = notices
        self.onAccessibilityDenied = onAccessibilityDenied
    }

    /// Регистрирует ⇧⌃⌥⌘G. Доступа Accessibility для этого не требуется:
    /// Carbon-хоткей срабатывает и до выдачи разрешения, поэтому нажатие
    /// доходит до нас и мы можем показать онбординг вместо тишины.
    public func registerHotKey() {
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_G),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        ) { [weak self] in
            self?.run()
        }
        Log.write(hotKey == nil ? "хоткей ⇧⌃⌥⌘G зарегистрировать НЕ удалось" : "хоткей ⇧⌃⌥⌘G зарегистрирован")
    }

    public func run() {
        guard !isRunning else {
            Log.write("повторное нажатие во время круга, пропущено")
            return
        }
        isRunning = true
        Task { @MainActor in
            await roundTrip()
            isRunning = false
        }
    }

    private func roundTrip() async {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        Log.section("хоткей: \(sourceApp?.localizedName ?? "неизвестно")")
        Log.write("флаги: \(ModifierFlags.describeCurrent()), способ вставки: \(settings.pasteMethod.rawValue)")

        // Доступ спрашивается заново на каждом круге: его можно отозвать в
        // системных настройках, и тогда круг обязан привести к онбордингу.
        guard Accessibility.isTrusted else {
            Log.write("доступа Accessibility нет, показываем онбординг")
            onAccessibilityDenied()
            return
        }

        // Без этой проверки защищённый ввод неотличим от пустого выделения:
        // события не доставляются молча, счётчик буфера не двигается, и человек
        // получает «ничего не выделено» там, где текст выделен.
        guard !SecureInput.isActive else {
            Log.write("защищённый ввод включён, захват невозможен")
            notices.show(.secureInputActive)
            return
        }

        guard let sourceApp else {
            notices.show(.unknownTargetApp)
            return
        }

        let result = await capture.capture()
        switch result.outcome {
        case .nothingSelected:
            // Сигнал сразу, а буфер защищаем дальше в фоне: быстрый отказ и
            // защита от опоздавшей копии — разные сроки.
            NSSound.beep()
            if settings.restoreClipboardAfterPaste {
                Task { @MainActor in await capture.restoreIfCopyLandsLate(after: result) }
            }

        case .unsupportedSelection:
            if settings.restoreClipboardAfterPaste {
                clipboard.restore(result.snapshot)
            }
            notices.show(.unsupportedSelection)

        case .captured(let text):
            let fixed = await transform.transform(text)
            let outcome = await paster.paste(
                fixed,
                into: sourceApp,
                method: settings.pasteMethod,
                restoreClipboard: settings.restoreClipboardAfterPaste,
                snapshot: result.snapshot
            )
            if case .failure(let error) = outcome {
                notices.show(error)
            }
        }
    }
}
