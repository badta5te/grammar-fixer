import AppKit
import Carbon.HIToolbox

@MainActor
public protocol SyntheticKeyboard {
    func copy()
    func paste()
    func type(_ text: String)
}

/// Синтетические нажатия через CGEvent.
///
/// Выводы прототипа, на которых стоит этот код:
///
/// - Ждать отпускания модификаторов не нужно. В момент срабатывания хоткея
///   зажаты все четыре, и план предсказывал, что ⌘C уедет как ⇧⌃⌥⌘C. На
///   macOS 15.7.7 этого не происходит, если выставить `flags` явно на самом
///   событии. Ожидание стоило медианы 192 мс и ничего не чинило.
/// - Источник `privateState` оставлен как дешёвая страховка: разницы в
///   поведении не нашлось, но он не зависит от состояния живой клавиатуры.
@MainActor
public final class SystemKeyboard: SyntheticKeyboard {
    /// Предел на длину строки в одном событии есть, поэтому набор режется.
    private let chunkSize = 20

    public init() {}

    public func copy() {
        send(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    public func paste() {
        send(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    /// Набор текста событиями, без участия буфера обмена. Заменяет выделение
    /// так же, как обычное печатание.
    public func type(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index ..< min(index + chunkSize, units.count)])
            index += chunk.count

            guard
                let keyDown = makeEvent(keyCode: 0, keyDown: true),
                let keyUp = makeEvent(keyCode: 0, keyDown: false)
            else { continue }

            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func send(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard
            let keyDown = makeEvent(keyCode: keyCode, keyDown: true),
            let keyUp = makeEvent(keyCode: keyCode, keyDown: false)
        else {
            Log.write("не удалось создать CGEvent")
            return
        }

        // Флаги выставляются явно на обеих половинах пары: именно так событие
        // выглядит как настоящее нажатие поверх зажатых модификаторов.
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func makeEvent(keyCode: CGKeyCode, keyDown: Bool) -> CGEvent? {
        CGEvent(
            keyboardEventSource: CGEventSource(stateID: .privateState),
            virtualKey: keyCode,
            keyDown: keyDown
        )
    }
}

public enum ModifierFlags {
    /// Что система видит зажатым прямо сейчас. Только для журнала.
    public static func describeCurrent() -> String {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskAlternate) { parts.append("alt") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        return parts.isEmpty ? "нет" : parts.joined(separator: "+")
    }
}
