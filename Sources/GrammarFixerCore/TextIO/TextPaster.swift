import AppKit

public enum PasteMethod: String, CaseIterable, Sendable {
    /// ⌘V. Fast and predictable, but the clipboard has to be taken over.
    case clipboard
    /// Typing the text as events. The clipboard is never touched.
    case typing
}

/// Pasting the result back into the source app.
///
/// The order matters more than any single step: focus first, then the paste,
/// and only then the clipboard restore.
@MainActor
public final class TextPaster {
    private let clipboard: Clipboard
    private let keyboard: SyntheticKeyboard
    private let focus: FocusRestoring
    private let activationTimeout: TimeInterval
    private let clipboardHoldDelay: TimeInterval
    private let sleep: @MainActor (TimeInterval) async -> Void

    /// - Parameter clipboardHoldDelay: how long to keep the result in the
    ///   clipboard after ⌘V. There is no way to learn when the target app has
    ///   read the clipboard, so the number here is unavoidably invented. It is
    ///   deliberately generous: restoring too early means pasting the previous
    ///   clipboard into somebody's document, while restoring too late merely
    ///   occupies the clipboard for a moment longer. Anyone who finds an
    ///   invented number unacceptable has `.typing`, which has none.
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
        // When typing, nobody needs the clipboard any more, so it is put back
        // at once with no reading to wait for.
        if method == .typing, restoreClipboard {
            clipboard.restore(snapshot)
        }
        if method == .clipboard {
            clipboard.write(text)
        }

        guard await focus.activate(app, timeout: activationTimeout) else {
            Log.write("focus did not come back, so the paste was called off rather than land in the wrong window")
            if method == .clipboard, restoreClipboard {
                clipboard.restore(snapshot)
            }
            return .failure(.focusLost)
        }
        Log.write("modifiers held before pasting: \(ModifierFlags.describeCurrent())")

        switch method {
        case .typing:
            keyboard.type(text)
            Log.write("round finished by typing, the clipboard was never touched")
        case .clipboard:
            keyboard.paste()
            if restoreClipboard {
                await sleep(clipboardHoldDelay)
                clipboard.restore(snapshot)
            }
            Log.write("round finished by pasting from the clipboard")
        }
        return .success(())
    }
}
