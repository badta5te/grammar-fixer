import AppKit

public enum PasteMethod: String, CaseIterable, Sendable {
    /// ⌘V. Быстро и предсказуемо, но буфер обмена приходится занять.
    case clipboard
    /// Набор текста событиями. Буфер не трогается вовсе.
    case typing
}

/// Вставка результата обратно в исходное приложение.
///
/// Порядок важнее любой отдельной операции: сначала фокус, потом вставка, и
/// только потом возврат буфера.
@MainActor
public final class TextPaster {
    private let clipboard: Clipboard
    private let keyboard: SyntheticKeyboard
    private let focus: FocusRestoring
    private let activationTimeout: TimeInterval
    private let clipboardHoldDelay: TimeInterval
    private let sleep: @MainActor (TimeInterval) async -> Void

    /// - Parameter clipboardHoldDelay: сколько держать результат в буфере после
    ///   ⌘V. Узнать, когда целевое приложение прочитало буфер, нечем, поэтому
    ///   число здесь неизбежно выдуманное. Выбрано с запасом намеренно: вернуть
    ///   буфер слишком рано значит вставить в чужой документ прошлое содержимое
    ///   буфера, а слишком поздно — всего лишь ненадолго занять буфер. Кому
    ///   выдуманное число неприемлемо, тому есть `.typing`, где его нет вовсе.
    public init(
        clipboard: Clipboard,
        keyboard: SyntheticKeyboard,
        focus: FocusRestoring,
        activationTimeout: TimeInterval = 1.5,
        clipboardHoldDelay: TimeInterval = 0.7,
        sleep: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.clipboard = clipboard
        self.keyboard = keyboard
        self.focus = focus
        self.activationTimeout = activationTimeout
        self.clipboardHoldDelay = clipboardHoldDelay
        self.sleep = sleep
    }

    public func paste(
        _ text: String,
        into app: NSRunningApplication,
        method: PasteMethod,
        restoreClipboard: Bool,
        snapshot: ClipboardSnapshot
    ) async -> Swift.Result<Void, RoundTripError> {
        // При наборе текста буфер больше никому не нужен, поэтому он
        // возвращается сразу, и ждать чтения не приходится.
        if method == .typing, restoreClipboard {
            clipboard.restore(snapshot)
        }
        if method == .clipboard {
            clipboard.write(text)
        }

        guard await focus.activate(app, timeout: activationTimeout) else {
            Log.write("фокус не вернулся — вставка отменена, чтобы не вставить не туда")
            if method == .clipboard, restoreClipboard {
                clipboard.restore(snapshot)
            }
            return .failure(.focusLost)
        }
        Log.write("флаги перед вставкой: \(ModifierFlags.describeCurrent())")

        switch method {
        case .typing:
            keyboard.type(text)
            Log.write("круг завершён набором текста, буфер обмена не менялся")
        case .clipboard:
            keyboard.paste()
            if restoreClipboard {
                await sleep(clipboardHoldDelay)
                clipboard.restore(snapshot)
            }
            Log.write("круг завершён вставкой из буфера")
        }
        return .success(())
    }
}
