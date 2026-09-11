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
            environment: environment,
            onAccessibilityDenied: { [weak self] in self?.deniedShown += 1 }
        )
    }

    /// Waits for the round to finish: it lives in a task of its own.
    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
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

    /// The ticket's central new case. By the time the model fails, the
    /// person's selection is already in the clipboard in place of whatever was
    /// there, because capture put it there. Without a restore, a network
    /// failure quietly eats the clipboard.
    func testFailedModelRestoresTheClipboard() async {
        transform.answer = .failure(LLMError.noConnection)
        makeController().run()
        await settle()

        XCTAssertEqual(clipboard.restored?.items.count, 1)
        XCTAssertEqual(notices.shown.map(\.title), [LLMError.noConnection.title])
        XCTAssertFalse(recorder.events.contains("paste"))
    }

    func testFailedModelLeavesTheClipboardAloneWhenRestoringIsOff() async {
        settings.restoreClipboardAfterPaste = false
        transform.answer = .failure(LLMError.timedOut)
        makeController().run()
        await settle()

        XCTAssertNil(clipboard.restored)
        XCTAssertEqual(notices.shown.map(\.title), [LLMError.timedOut.title])
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
