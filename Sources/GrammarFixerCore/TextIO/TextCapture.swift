import Foundation

/// Capturing the selection: from the system where that works, and with a
/// synthetic ⌘C everywhere else.
///
/// Failure is detected by the clipboard's change count, not by elapsed time.
/// Without that, "nothing was selected" would quietly mean correcting
/// yesterday's clipboard and pasting it into somebody else's app.
///
/// The order is inviolable: **nothing is written to the clipboard before a
/// confirmed increment.**
@MainActor
public final class TextCapture {
    public enum Outcome: Equatable, Sendable {
        case captured(String)
        /// The change count never moved: there was nothing to copy.
        case nothingSelected
        /// The change count moved but there is no text. Found in Chrome on a
        /// non-text selection: without this branch a nil would travel onward.
        case unsupportedSelection
    }

    public struct Result: Sendable {
        public let outcome: Outcome
        public let snapshot: ClipboardSnapshot
        public let changeCountBefore: Int
        /// Whether capturing went through the clipboard. It did not when the
        /// system handed the selection over, and then there is nothing of ours
        /// in the clipboard to put back afterwards — putting the snapshot back
        /// would be a write to a clipboard this round never touched.
        public let touchedClipboard: Bool
    }

    private let clipboard: Clipboard
    private let keyboard: SyntheticKeyboard
    private let reader: (any SelectionReading)?
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval
    private let lateCopyWindow: TimeInterval
    private let sleep: @MainActor (TimeInterval) async -> Void

    /// - Parameters:
    ///   - timeout: how long to wait for the increment. The prototype produced
    ///     30 measurements with a median of 34 ms and a maximum of 146 ms, and
    ///     the second that used to stand here read as "the app did not react".
    ///     Half a second is three times the observed maximum. The cost of being
    ///     wrong is lopsided: too short a timeout declares "nothing selected"
    ///     where there was text.
    ///   - lateCopyWindow: how much longer to watch the clipboard after giving
    ///     up. A copy that arrives late would otherwise quietly leave the
    ///     person's selection in their clipboard in place of what was there.
    ///     The window is deliberately shorter than the wait itself: the further
    ///     from our own ⌘C, the likelier it is that somebody else changed the
    ///     clipboard, and then the guard does harm instead of good.
    public init(
        clipboard: Clipboard,
        keyboard: SyntheticKeyboard,
        /// The system, asked before the clipboard. Left out means copying, as
        /// it always did.
        reader: (any SelectionReading)? = nil,
        pollInterval: TimeInterval = 0.01,
        timeout: TimeInterval = 0.5,
        lateCopyWindow: TimeInterval = 0.5,
        sleep: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.clipboard = clipboard
        self.keyboard = keyboard
        self.reader = reader
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.lateCopyWindow = lateCopyWindow
        self.sleep = sleep
    }

    /// - Parameter readingDirectly: whether to ask the system for the
    ///   selection first. Off is for anybody whose app answers with something
    ///   other than what is selected: correcting the wrong text is worse than
    ///   touching the clipboard.
    public func capture(readingDirectly: Bool = true) async -> Result {
        // Taken even when the system answers: pasting the correction back goes
        // through the clipboard, and an empty snapshot put back after that
        // would wipe whatever somebody had in it.
        let snapshot = clipboard.snapshot()
        let before = clipboard.changeCount
        Log.write("clipboard snapshot: items \(snapshot.items.count), types \(snapshot.typeCount)")

        // A blank answer cannot be told apart from an app that does not
        // support being asked, so it is never allowed to mean "nothing is
        // selected". That verdict belongs to the change count, which is the
        // one thing here that has never been wrong.
        if readingDirectly, let text = reader?.selectedText(), !text.trimmed.isEmpty {
            return Result(
                outcome: .captured(text),
                snapshot: snapshot,
                changeCountBefore: before,
                touchedClipboard: false
            )
        }

        keyboard.copy()

        let start = Date()
        for _ in 0 ..< polls(within: timeout) {
            await sleep(pollInterval)
            guard clipboard.changeCount != before else { continue }

            Log.write(String(format: "clipboard changed in %.0f ms", Date().timeIntervalSince(start) * 1000))
            guard let text = clipboard.readText(), !text.isEmpty else {
                return Result(
                    outcome: .unsupportedSelection,
                    snapshot: snapshot,
                    changeCountBefore: before,
                    touchedClipboard: true
                )
            }
            Log.write("captured characters: \(text.count)")
            return Result(
                outcome: .captured(text),
                snapshot: snapshot,
                changeCountBefore: before,
                touchedClipboard: true
            )
        }

        Log.write("the clipboard count did not move in \(Int(timeout * 1000)) ms, so nothing was selected")
        return Result(
            outcome: .nothingSelected,
            snapshot: snapshot,
            changeCountBefore: before,
            touchedClipboard: true
        )
    }

    /// Watches the clipboard after a refusal and puts the contents back if ⌘C
    /// did arrive after all. The beep has already sounded by then: a quick
    /// refusal and protecting the clipboard run on different clocks, and the
    /// two must not be merged.
    ///
    /// Somebody else's copy landing inside this window will be overwritten by
    /// the guard. The case is not hypothetical: in a terminal with
    /// `copy-on-select` the selection goes to the clipboard by itself, and
    /// selecting text right after a shortcut that did not fire made that copy
    /// disappear. That is why the window is cut to half a second.
    @discardableResult
    public func restoreIfCopyLandsLate(after result: Result) async -> Bool {
        for _ in 0 ..< polls(within: lateCopyWindow) {
            await sleep(pollInterval)
            guard clipboard.changeCount != result.changeCountBefore else { continue }
            Log.write("the copy arrived after we gave up, so the clipboard goes back")
            return clipboard.restore(result.snapshot)
        }
        return false
    }

    private func polls(within duration: TimeInterval) -> Int {
        max(1, Int((duration / pollInterval).rounded()))
    }
}
