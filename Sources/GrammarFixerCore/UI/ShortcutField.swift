import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The field that records a combination.
///
/// AppKit rather than SwiftUI, for the same reason the result panel handles
/// keys itself: a keypress with nowhere to land never reaches a view, and the
/// combinations worth recording are precisely the ones the window would
/// otherwise act on. `performKeyEquivalent` is where ⌘-combinations can be
/// taken before the main menu gets them — without it, recording ⌘Q would quit
/// the app instead.
struct ShortcutField: NSViewRepresentable {
    let shortcut: Shortcut
    /// Called while the field listens, so the global hot key can be let go:
    /// it fires wherever the keyboard is pointing, our own window included.
    let onRecording: (Bool) -> Void
    let onRecorded: (Shortcut) -> Void

    func makeNSView(context: Context) -> RecordingButton {
        let button = RecordingButton()
        button.bezelStyle = .rounded
        button.onRecording = onRecording
        button.onRecorded = onRecorded
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: RecordingButton, context: Context) {
        button.onRecording = onRecording
        button.onRecorded = onRecorded
        // Not while it is listening: the title then says what it is waiting
        // for, and a redraw of the window would wipe that away.
        if !button.isRecording { button.shortcut = shortcut }
    }
}

final class RecordingButton: NSButton {
    var onRecording: (Bool) -> Void = { _ in }
    var onRecorded: (Shortcut) -> Void = { _ in }

    private(set) var isRecording = false {
        didSet {
            title = isRecording ? "Press a combination…" : shortcut.display
            onRecording(isRecording)
        }
    }

    var shortcut: Shortcut = .default {
        didSet { if !isRecording { title = shortcut.display } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(startRecording)
        title = shortcut.display
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        guard !isRecording else {
            isRecording = false
            return
        }
        isRecording = true
        window?.makeFirstResponder(self)
    }

    /// Clicking elsewhere, or closing the window, stops the listening. Without
    /// this the hot key would stay let go and the shortcut would be dead until
    /// the next launch.
    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        isRecording = false

        // Escape on its own means "never mind". It is also a combination
        // somebody might want with modifiers, so only the bare key backs out.
        let modifiers = Shortcut.Modifiers(event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty { return }

        onRecorded(Shortcut(event: event))
    }
}
