import AppKit

/// The whole round trip: shortcut, capture, correction by the model, paste.
///
/// Every way out of here ends in something, whether a beep, a message or the
/// onboarding screen. Not one silent failure is left: a silent failure here
/// means somebody is waiting for a result that will never come.
@MainActor
public final class RoundTripController {
    private let settings: Settings
    private let clipboard: Clipboard
    private let capture: TextCapture
    private let paster: TextPaster
    private let transform: TextTransforming
    private let notices: any NoticePresenting
    private let results: any ResultPresenting
    private let environment: any RoundTripEnvironment
    private let budget: @MainActor () -> BudgetNotice?
    private let onAccessibilityDenied: () -> Void

    private var isRunning = false

    public init(
        settings: Settings,
        clipboard: Clipboard,
        capture: TextCapture,
        paster: TextPaster,
        transform: TextTransforming,
        notices: any NoticePresenting,
        results: any ResultPresenting,
        /// Where the month stands, read afresh while the panel is open so the
        /// round that passes the limit is the round that says so.
        budget: @escaping @MainActor () -> BudgetNotice? = { nil },
        environment: any RoundTripEnvironment = SystemEnvironment(),
        onAccessibilityDenied: @escaping () -> Void
    ) {
        self.settings = settings
        self.clipboard = clipboard
        self.capture = capture
        self.paster = paster
        self.transform = transform
        self.notices = notices
        self.results = results
        self.environment = environment
        self.budget = budget
        self.onAccessibilityDenied = onAccessibilityDenied
    }

    public func run() {
        guard !isRunning else {
            // A round trip with a model takes seconds. A second press happens
            // precisely because no result is visible yet, and silence in reply
            // reads as "the shortcut is broken".
            Log.write("pressed again during a round, ignored")
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
        Log.section("shortcut: \(sourceApp?.localizedName ?? "unknown")")
        Log.write("modifiers: \(ModifierFlags.describeCurrent()), paste method: \(settings.pasteMethod.rawValue)")

        // Access is checked again on every round: it can be revoked in System
        // Settings, and then the round trip has to lead to onboarding.
        guard environment.isAccessibilityTrusted else {
            Log.write("no Accessibility access, showing the onboarding screen")
            onAccessibilityDenied()
            return
        }

        // Without this check secure input is indistinguishable from an empty
        // selection: events are dropped silently, the clipboard change count
        // never moves, and the person is told nothing was selected while their
        // text plainly is.
        guard !environment.isSecureInputActive else {
            Log.write("secure input is on, so capture is impossible")
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
            // The beep comes at once while the clipboard is watched for
            // another half second: a quick refusal and the guard against a
            // late copy are on different clocks.
            environment.beep()
            if settings.restoreClipboardAfterPaste {
                // The guard deliberately holds the round open. Letting it go
                // in a task of its own would allow the next round to start
                // while this one can still touch the clipboard, and a stale
                // snapshot would land on top of a fresh capture.
                await capture.restoreIfCopyLandsLate(after: result)
            }

        case .unsupportedSelection:
            // The same beep as an empty selection, on purpose. A window here
            // would explain what the person can already see, and cost them a
            // click to put away. Which of the two cases it was stays in the
            // log, where it is diagnosis rather than news.
            Log.write("the selection did not arrive as text")
            environment.beep()
            if settings.restoreClipboardAfterPaste {
                clipboard.restore(result.snapshot)
            }

        case .captured(let text):
            await correct(text, in: sourceApp, snapshot: result.snapshot)
        }
    }

    /// The correction is shown before it goes anywhere. Nothing is pasted on
    /// its own any more: the round ends where the person decides it ends.
    private func correct(_ text: String, in sourceApp: NSRunningApplication, snapshot: ClipboardSnapshot) async {
        let session = CorrectionSession(
            source: text,
            produce: { [transform] in transform.stream($0) },
            budget: budget
        )
        session.start()

        // Read before the panel appears and kept for the dismissal: the
        // clipboard holds the captured selection all the while the panel is
        // open, and the panel is open for as long as the person likes.
        let changeCountAfterCapture = clipboard.changeCount

        let decision = await results.present(session)
        // The stream may still be running when the panel goes: an answer read
        // into nothing is still an answer being paid for.
        session.cancel()

        switch decision {
        case .paste(let fixed):
            // Typing puts nothing of ours into the clipboard, so restoring
            // there is only right while the clipboard is still the one we took
            // over. Pasting overwrites it in any case, and a copy made while
            // the panel stood open is lost either way.
            let mayRestore = settings.restoreClipboardAfterPaste
                && (settings.pasteMethod == .clipboard
                    || clipboardStillHoldsCapture(text, since: changeCountAfterCapture))
            let outcome = await paster.paste(
                fixed,
                into: sourceApp,
                method: settings.pasteMethod,
                restoreClipboard: mayRestore,
                snapshot: snapshot
            )
            if case .failure(let error) = outcome {
                notices.show(error)
            }

        case .copy(let fixed):
            // No restore on purpose. Putting the previous contents back would
            // undo the one thing that was asked for.
            clipboard.write(fixed)
            Log.write("the result went to the clipboard, nothing was pasted")

        case .dismissed:
            Log.write("the panel was closed, nothing was pasted")
            restoreCapturedSelection(
                snapshot,
                capturedText: text,
                unlessChangedSince: changeCountAfterCapture
            )
        }
    }

    /// Puts the clipboard back after a round that pasted nothing — but only if
    /// it is still ours to put back. The panel can stand open for a minute, and
    /// in that minute the person may copy something of their own. Restoring
    /// over a fresh copy is the harm the late-copy guard was written against,
    /// only with a far longer window.
    ///
    /// The change count alone is too strict a test. A terminal with
    /// copy-on-select moves the count again right after our own ⌘C, and the
    /// very first live round in Ghostty refused to give the clipboard back for
    /// exactly that reason. What matters is not how many times the clipboard
    /// changed but whether anything of the person's is sitting in it now.
    private func restoreCapturedSelection(
        _ snapshot: ClipboardSnapshot,
        capturedText: String,
        unlessChangedSince changeCount: Int
    ) {
        guard settings.restoreClipboardAfterPaste else { return }
        guard clipboardStillHoldsCapture(capturedText, since: changeCount) else {
            Log.write("the clipboard holds somebody else's copy, so the snapshot stays where it is")
            return
        }
        clipboard.restore(snapshot)
    }

    /// Whether the clipboard is still the one this round took over. Either it
    /// has not moved since the capture, or what is in it is still the captured
    /// selection: counting changes alone is too strict, because a terminal with
    /// copy-on-select moves the count again right after our own ⌘C.
    private func clipboardStillHoldsCapture(_ capturedText: String, since changeCount: Int) -> Bool {
        clipboard.changeCount == changeCount || clipboard.readText() == capturedText
    }
}
