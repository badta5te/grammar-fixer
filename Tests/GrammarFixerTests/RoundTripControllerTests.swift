import AppKit
import XCTest
@testable import GrammarFixerCore

/// The whole round trip. What is under test is not that it works but that
/// every way out of it ends in something: a silent failure here means somebody
/// is waiting for their selection to be replaced and it never will be.
@MainActor
final class RoundTripControllerTests: XCTestCase {
    private var recorder: Recorder!
    private var clipboard: FakeClipboard!
    private var keyboard: FakeKeyboard!
    private var clock: FakeClock!
    private var environment: FakeEnvironment!
    private var notices: FakeNotices!
    private var transform: FakeTransform!
    private var results: FakeResults!
    private var settings: Settings!
    private var deniedShown = 0

    override func setUp() async throws {
        recorder = Recorder()
        clipboard = FakeClipboard(recorder: recorder, snapshot: ClipboardSnapshot(items: [
            ClipboardSnapshot.Item(payloads: ["public.utf8-plain-text": Data("прежнее".utf8)]),
        ]))
        keyboard = FakeKeyboard(recorder: recorder)
        clock = FakeClock()
        environment = FakeEnvironment(recorder: recorder)
        notices = FakeNotices()
        transform = FakeTransform(recorder: recorder)
        results = FakeResults(recorder: recorder)
        settings = Settings(defaults: UserDefaults(suiteName: "RoundTripControllerTests")!)
        settings.restoreClipboardAfterPaste = true
        settings.pasteMethod = .clipboard
        deniedShown = 0

        // Capture succeeds: on the third polling tick the clipboard change
        // count moves.
        clock.onTick = { [clipboard] tick in
            if tick == 3 { clipboard!.simulateCopy("выделенный текст") }
        }
    }

    private func makeController() -> RoundTripController {
        RoundTripController(
            settings: settings,
            clipboard: clipboard,
            capture: TextCapture(
                clipboard: clipboard,
                keyboard: keyboard,
                pollInterval: 0.001,
                timeout: 0.05,
                lateCopyWindow: 0.01,
                sleep: { [clock] in await clock!.sleep($0) }
            ),
            paster: TextPaster(
                clipboard: clipboard,
                keyboard: keyboard,
                focus: FakeFocusRestorer(recorder: recorder),
                clipboardHoldDelay: 0,
                sleep: { _ in }
            ),
            transform: transform,
            notices: notices,
            results: results,
            environment: environment,
            onAccessibilityDenied: { [weak self] in self?.deniedShown += 1 }
        )
    }

    /// Waits for the round to finish: it lives in a task of its own. The count
    /// is generous because a round is now several tasks deep — capture polls,
    /// the model answers, the panel waits — and a count that merely happens to
    /// be enough today turns into a test that fails on a loaded machine.
    private func settle() async {
        for _ in 0..<2000 { await Task.yield() }
    }

    func testFixedTextIsPastedBack() async {
        transform.answer = .success("Выделенный текст.")
        makeController().run()
        await settle()

        XCTAssertEqual(transform.received, ["выделенный текст"])
        // The order is what breaks unnoticed: restoring the snapshot before
        // the paste means pasting the previous clipboard into a document.
        XCTAssertEqual(
            recorder.events.filter { ["transform", "write", "paste", "restore"].contains($0) },
            ["transform", "write", "paste", "restore"]
        )
        XCTAssertEqual(clipboard.restored?.items.count, 1)
        XCTAssertTrue(notices.shown.isEmpty)
    }

    /// A refusal now belongs in the panel: the person is already looking at
    /// it, waiting for their text. A window beside it would be a second thing
    /// to dismiss saying the same thing.
    func testAFailedModelIsShownInThePanelRatherThanAWindow() async {
        transform.answer = .failure(LLMError.noConnection)
        results.decide = { _ in .dismissed }
        makeController().run()
        await settle()

        XCTAssertEqual(
            results.presented.first?.state,
            .failed(title: LLMError.noConnection.title, message: LLMError.noConnection.message)
        )
        XCTAssertTrue(notices.shown.isEmpty)
        XCTAssertFalse(recorder.events.contains("paste"))
    }

    /// By the time the model fails, the person's selection is already in the
    /// clipboard in place of whatever was there, because capture put it there.
    /// Without a restore, a dropped connection quietly eats the clipboard.
    func testAClosedPanelGivesTheClipboardBack() async {
        transform.answer = .failure(LLMError.noConnection)
        results.decide = { _ in .dismissed }
        makeController().run()
        await settle()

        XCTAssertEqual(clipboard.restored?.items.count, 1)
    }

    func testTheClipboardIsLeftAloneWhenRestoringIsOff() async {
        settings.restoreClipboardAfterPaste = false
        transform.answer = .failure(LLMError.timedOut)
        results.decide = { _ in .dismissed }
        makeController().run()
        await settle()

        XCTAssertNil(clipboard.restored)
    }

    /// ⌘⏎ takes the clipboard over on purpose, so putting the previous
    /// contents back would undo the only thing that was asked for.
    func testCopyingTakesTheClipboardAndPastesNothing() async {
        transform.answer = .success("Выделенный текст.")
        results.decide = { .copy($0.result ?? "") }
        makeController().run()
        await settle()

        XCTAssertEqual(clipboard.text, "Выделенный текст.")
        XCTAssertFalse(recorder.events.contains("paste"))
        XCTAssertFalse(recorder.events.contains("restore"))
        XCTAssertTrue(notices.shown.isEmpty)
    }

    /// The panel can stand open for a minute, and in that minute the person may
    /// copy something of their own. Putting the snapshot back on top of it is
    /// the same harm the late-copy guard exists to prevent.
    func testAFreshCopyMadeWhileThePanelWasOpenSurvives() async {
        results.decide = { [clipboard] _ in
            clipboard!.simulateCopy("скопировано человеком")
            return .dismissed
        }
        makeController().run()
        await settle()

        XCTAssertNil(clipboard.restored)
        XCTAssertEqual(clipboard.text, "скопировано человеком")
    }

    /// The count alone is too strict a test. A terminal with copy-on-select
    /// moves it again right after our own ⌘C, and the first live round in
    /// Ghostty refused to give the clipboard back for that reason. What is in
    /// the clipboard decides, not how often it changed.
    func testAnotherChangeHoldingOurOwnSelectionStillRestores() async {
        results.decide = { [clipboard] _ in
            clipboard!.simulateCopy("выделенный текст")
            return .dismissed
        }
        makeController().run()
        await settle()

        XCTAssertEqual(clipboard.restored?.items.count, 1)
    }

    /// A decision that never arrives would leave the round open and the
    /// shortcut dead until a restart. Closing the panel has to free it.
    func testAClosedPanelLeavesTheShortcutWorking() async {
        // Two rounds, so the copy has to happen twice: the counter runs on
        // through the whole test and a one-off would make the second round
        // fail for a reason this test is not about.
        clock.onTick = { [clipboard] tick in
            if tick % 3 == 0 { clipboard!.simulateCopy("выделенный текст") }
        }
        results.decide = { _ in .dismissed }
        let controller = makeController()
        controller.run()
        await settle()

        controller.run()
        await settle()

        XCTAssertEqual(results.presented.count, 2)
        XCTAssertEqual(environment.beeps, 0)
    }

    /// A round with a model takes seconds, not milliseconds. A second press
    /// during that time happens precisely because no result is visible, and it
    /// has to answer with something.
    func testSecondPressDuringTheRoundIsAnswered() async {
        transform.waitsForRelease = true
        let controller = makeController()
        controller.run()
        await settle()

        controller.run()
        await settle()

        XCTAssertEqual(environment.beeps, 1)
        transform.release()
        await settle()
        XCTAssertTrue(recorder.events.contains("paste"))
    }

    /// A selection that did not arrive as text gets the same beep as an empty
    /// one. A window would explain what the person can already see and would
    /// cost them a click to dismiss.
    func testSelectionThatIsNotTextBeepsWithoutAWindow() async {
        clock.onTick = { [clipboard] tick in
            if tick == 3 { clipboard!.simulateCopy(nil) }
        }
        makeController().run()
        await settle()

        XCTAssertEqual(environment.beeps, 1)
        XCTAssertTrue(notices.shown.isEmpty)
        XCTAssertEqual(clipboard.restored?.items.count, 1)
        XCTAssertTrue(transform.received.isEmpty)
    }

    func testDeniedAccessLeadsToOnboardingInsteadOfSilence() async {
        environment.isAccessibilityTrusted = false
        makeController().run()
        await settle()

        XCTAssertEqual(deniedShown, 1)
        XCTAssertFalse(recorder.events.contains("copy"))
    }

    func testSecureInputIsNamedRatherThanMistakenForAnEmptySelection() async {
        environment.isSecureInputActive = true
        makeController().run()
        await settle()

        XCTAssertEqual(notices.shown.map(\.title), [RoundTripError.secureInputActive.title])
        XCTAssertFalse(recorder.events.contains("copy"))
    }

    func testEmptySelectionBeepsAndWritesNothing() async {
        clock.onTick = { _ in }
        makeController().run()
        await settle()

        XCTAssertEqual(environment.beeps, 1)
        XCTAssertFalse(recorder.events.contains("write"))
        XCTAssertTrue(transform.received.isEmpty)
    }
}
