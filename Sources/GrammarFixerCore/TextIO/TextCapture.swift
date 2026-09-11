import Foundation

/// Capturing the selection with a synthetic ⌘C.
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
    }

    private let clipboard: Clipboard
    private let keyboard: SyntheticKeyboard
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
        pollInterval: TimeInterval = 0.01,
        timeout: TimeInterval = 0.5,
        lateCopyWindow: TimeInterval = 0.5,
        sleep: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.clipboard = clipboard
        self.keyboard = keyboard
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.lateCopyWindow = lateCopyWindow
        self.sleep = sleep
    }

    public func capture() async -> Result {
        let snapshot = clipboard.snapshot()
        let before = clipboard.changeCount
        Log.write("снимок буфера: элементов \(snapshot.items.count), типов \(snapshot.typeCount)")

        keyboard.copy()

        let start = Date()
        for _ in 0 ..< polls(within: timeout) {
            await sleep(pollInterval)
            guard clipboard.changeCount != before else { continue }

            Log.write(String(format: "буфер обновился за %.0f мс", Date().timeIntervalSince(start) * 1000))
            guard let text = clipboard.readText(), !text.isEmpty else {
                return Result(outcome: .unsupportedSelection, snapshot: snapshot, changeCountBefore: before)
            }
            Log.write("захвачено символов: \(text.count)")
            return Result(outcome: .captured(text), snapshot: snapshot, changeCountBefore: before)
        }

        Log.write("счётчик буфера не сдвинулся за \(Int(timeout * 1000)) мс — выделения нет")
        return Result(outcome: .nothingSelected, snapshot: snapshot, changeCountBefore: before)
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
            Log.write("копия приехала после отказа, буфер возвращается на место")
            return clipboard.restore(result.snapshot)
        }
        return false
    }

    private func polls(within duration: TimeInterval) -> Int {
        max(1, Int((duration / pollInterval).rounded()))
    }
}
