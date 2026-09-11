import AppKit
import Carbon.HIToolbox

/// Круг целиком: хоткей, захват, исправление моделью, вставка.
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
    private let notices: any NoticePresenting
    private let environment: any RoundTripEnvironment
    private let onAccessibilityDenied: () -> Void

    private var hotKey: HotKey?
    private var isRunning = false

    public init(
        settings: Settings,
        clipboard: Clipboard,
        capture: TextCapture,
        paster: TextPaster,
        transform: TextTransforming,
        notices: any NoticePresenting,
        environment: any RoundTripEnvironment = SystemEnvironment(),
        onAccessibilityDenied: @escaping () -> Void
    ) {
        self.settings = settings
        self.clipboard = clipboard
        self.capture = capture
        self.paster = paster
        self.transform = transform
        self.notices = notices
        self.environment = environment
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
        guard hotKey == nil else {
            Log.write("хоткей ⇧⌃⌥⌘G зарегистрирован")
            return
        }
        // Комбинацию мог занять кто-то другой — тот же Raycast, ради отказа от
        // которого всё затевалось. Без сообщения человек получает приложение,
        // которое просто ничего не делает, и никакого способа это понять.
        Log.write("хоткей ⇧⌃⌥⌘G зарегистрировать НЕ удалось")
        notices.show(RoundTripError.hotKeyUnavailable)
    }

    public func run() {
        guard !isRunning else {
            // Круг с моделью длится секунды. Второе нажатие человек делает
            // именно потому, что не видит результата, и молчание в ответ
            // читается как «хоткей сломался».
            Log.write("повторное нажатие во время круга, пропущено")
            environment.beep()
            return
        }
        isRunning = true
        Task { @MainActor in
            await roundTrip()
            isRunning = false
        }
    }

    private func roundTrip() async {
        let sourceApp = environment.frontmostApplication
        Log.section("хоткей: \(sourceApp?.localizedName ?? "неизвестно")")
        Log.write("флаги: \(ModifierFlags.describeCurrent()), способ вставки: \(settings.pasteMethod.rawValue)")

        // Доступ спрашивается заново на каждом круге: его можно отозвать в
        // системных настройках, и тогда круг обязан привести к онбордингу.
        guard environment.isAccessibilityTrusted else {
            Log.write("доступа Accessibility нет, показываем онбординг")
            onAccessibilityDenied()
            return
        }

        // Без этой проверки защищённый ввод неотличим от пустого выделения:
        // события не доставляются молча, счётчик буфера не двигается, и человек
        // получает «ничего не выделено» там, где текст выделен.
        guard !environment.isSecureInputActive else {
            Log.write("защищённый ввод включён, захват невозможен")
            notices.show(RoundTripError.secureInputActive)
            return
        }

        guard let sourceApp else {
            notices.show(RoundTripError.unknownTargetApp)
            return
        }

        let result = await capture.capture()
        switch result.outcome {
        case .nothingSelected:
            // Сигнал сразу, а присмотр за буфером продолжается ещё полсекунды:
            // быстрый отказ и защита от опоздавшей копии — разные сроки.
            environment.beep()
            if settings.restoreClipboardAfterPaste {
                // Присмотр держит круг открытым намеренно. Отпустить его в
                // отдельную задачу значило бы разрешить следующему кругу
                // начаться, пока этот ещё может тронуть буфер, и тогда чужой
                // снимок лёг бы поверх свежего захвата.
                await capture.restoreIfCopyLandsLate(after: result)
            }

        case .unsupportedSelection:
            if settings.restoreClipboardAfterPaste {
                clipboard.restore(result.snapshot)
            }
            notices.show(RoundTripError.unsupportedSelection)

        case .captured(let text):
            await fix(text, in: sourceApp, snapshot: result.snapshot)
        }
    }

    private func fix(_ text: String, in sourceApp: NSRunningApplication, snapshot: ClipboardSnapshot) async {
        let fixed: String
        do {
            fixed = try await transform.transform(text)
        } catch {
            // К этому месту выделение человека уже лежит в буфере обмена: его
            // положил туда захват. Отказ модели без возврата снимка означал бы,
            // что оборвавшаяся сеть молча съела содержимое буфера.
            if settings.restoreClipboardAfterPaste {
                clipboard.restore(snapshot)
            }
            let failure = (error as? any UserFacingError) ?? LLMError.from(error)
            Log.write("исправление не состоялось: \(failure.title)")
            notices.show(failure)
            return
        }

        let outcome = await paster.paste(
            fixed,
            into: sourceApp,
            method: settings.pasteMethod,
            restoreClipboard: settings.restoreClipboardAfterPaste,
            snapshot: snapshot
        )
        if case .failure(let error) = outcome {
            notices.show(error)
        }
    }
}
