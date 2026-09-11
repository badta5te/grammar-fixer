import AppKit
import Carbon.HIToolbox

@MainActor
public protocol SyntheticKeyboard {
    func copy()
    func paste()
    func type(_ text: String)
}

/// Synthetic key presses through CGEvent.
///
/// The prototype findings this code stands on:
///
/// - There is no need to wait for the modifiers to be released. All four are
///   held down when the shortcut fires, and the plan predicted ⌘C would leave
///   as ⇧⌃⌥⌘C. On macOS 15.7.7 that does not happen as long as `flags` is set
///   explicitly on the event itself. Waiting cost a median of 192 ms and fixed
///   nothing.
/// - The `privateState` source is kept as cheap insurance: no difference in
///   behaviour was found, but it does not depend on the state of a live
///   keyboard.
@MainActor
public final class SystemKeyboard: SyntheticKeyboard {
    /// There is a limit on the string length of a single event, so typing is
    /// cut into chunks.
    private let chunkSize = 20

    /// Apps that process input asynchronously drop characters when chunks
    /// arrive back to back. The pause is small enough to be invisible.
    private let chunkPause: TimeInterval = 0.004

    public init() {}

    public func copy() {
        send(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    public func paste() {
        send(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    /// Typing text as events, with no clipboard involved. Replaces the
    /// selection the same way ordinary typing does.
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

            // A pause between chunks. Typing has no delivery confirmation,
            // unlike capture with its clipboard change count, so the only
            // defence against losing characters at a seam is not to fire the
            // events back to back. A paragraph costs about forty milliseconds.
            if index < units.count { Thread.sleep(forTimeInterval: chunkPause) }
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

        // The flags are set explicitly on both halves of the pair: that is
        // what makes the event look like a real press on top of held-down
        // modifiers.
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
    /// What the system sees held down right now. For the log only.
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
