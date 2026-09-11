import XCTest
@testable import GrammarFixerCore

/// Capture is where a silent failure costs the most: mistaking "nothing was
/// selected" for success sends yesterday's clipboard into somebody's app.
@MainActor
final class TextCaptureTests: XCTestCase {
    private var recorder: Recorder!
    private var clipboard: FakeClipboard!
    private var keyboard: FakeKeyboard!
    private var clock: FakeClock!

    override func setUp() async throws {
        recorder = Recorder()
        clipboard = FakeClipboard(recorder: recorder)
        keyboard = FakeKeyboard(recorder: recorder)
        clock = FakeClock()
    }

    private func makeCapture(
        timeout: TimeInterval = 0.05,
        lateCopyWindow: TimeInterval = 0.1,
        reader: (any SelectionReading)? = nil
    ) -> TextCapture {
        TextCapture(
            clipboard: clipboard,
            keyboard: keyboard,
            reader: reader,
            pollInterval: 0.01,
            timeout: timeout,
            lateCopyWindow: lateCopyWindow,
            sleep: { [clock] in await clock!.sleep($0) }
        )
    }

    func testSnapshotIsTakenBeforeTheCopyIsSent() async {
        clock.onTick = { [clipboard] _ in clipboard!.simulateCopy("hello") }

        _ = await makeCapture().capture()

        XCTAssertEqual(recorder.events.prefix(2).map { $0 }, ["snapshot", "copy"])
    }

    func testCapturedTextIsReturnedOnceTheChangeCountMoves() async {
        clock.onTick = { [clipboard] tick in
            if tick == 3 { clipboard!.simulateCopy("выделенный текст") }
        }

        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .captured("выделенный текст"))
    }

    /// The trap from the plan: without the change count, "nothing selected" is
    /// indistinguishable from success.
    func testNothingSelectedWhenTheChangeCountNeverMoves() async {
        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .nothingSelected)
        XCTAssertNil(clipboard.restored, "nothing is written to the clipboard before a confirmed increment")
    }

    /// Found in Chrome: the change count moved but there is no string in the
    /// clipboard, because the selection was not text.
    func testNonTextualSelectionIsReportedSeparately() async {
        clock.onTick = { [clipboard] _ in clipboard!.simulateCopy(nil) }

        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .unsupportedSelection)
    }

    func testEmptyStringCountsAsNonTextualSelection() async {
        clock.onTick = { [clipboard] _ in clipboard!.simulateCopy("") }

        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .unsupportedSelection)
    }

    /// A copy can arrive after we have given up. The person's selection then
    /// quietly stays in their clipboard in place of what was there.
    func testLateCopyRestoresTheClipboard() async {
        let capture = makeCapture()
        let result = await capture.capture()
        XCTAssertEqual(result.outcome, .nothingSelected)

        clock.onTick = { [clipboard] tick in
            if tick == 8 { clipboard!.simulateCopy("приехало с опозданием") }
        }
        let restored = await capture.restoreIfCopyLandsLate(after: result)

        XCTAssertTrue(restored)
        XCTAssertEqual(clipboard.restored, result.snapshot)
    }

    func testLateCopyGuardDoesNothingWhenNoCopyArrives() async {
        let capture = makeCapture()
        let result = await capture.capture()

        let restored = await capture.restoreIfCopyLandsLate(after: result)

        XCTAssertFalse(restored)
        XCTAssertNil(clipboard.restored)
    }
}


/// Reading the selection out of the system instead of copying it.
///
/// Worth having because it removes the clipboard from the round entirely in
/// the apps that support it. Support is uneven, especially in anything built
/// on web technology, so it is an attempt: nothing usable comes back and the
/// proven path through a synthetic ⌘C runs as before.
@MainActor
final class DirectSelectionTests: XCTestCase {
    private var recorder: Recorder!
    private var clipboard: FakeClipboard!
    private var keyboard: FakeKeyboard!
    private var clock: FakeClock!
    private var reader: FakeSelectionReader!

    override func setUp() async throws {
        recorder = Recorder()
        clipboard = FakeClipboard(recorder: recorder)
        keyboard = FakeKeyboard(recorder: recorder)
        clock = FakeClock()
        reader = FakeSelectionReader(recorder: recorder)
        // A copy would succeed, so any test that ends up copying says so
        // rather than merely failing to find text.
        clock.onTick = { [clipboard] tick in
            if tick == 2 { clipboard!.simulateCopy("что скопировалось") }
        }
    }

    private func makeCapture() -> TextCapture {
        TextCapture(
            clipboard: clipboard,
            keyboard: keyboard,
            reader: reader,
            pollInterval: 0.01,
            timeout: 0.05,
            lateCopyWindow: 0.1,
            sleep: { [clock] in await clock!.sleep($0) }
        )
    }

    /// The whole point: in an app that answers, the clipboard is not read, not
    /// written and not put back. Nothing of somebody's own can be lost by a
    /// round that never touches it.
    func testAnAnsweringAppLeavesTheClipboardAlone() async {
        reader.selection = "выделенный текст"

        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .captured("выделенный текст"))
        XCTAssertFalse(result.touchedClipboard)
        XCTAssertFalse(recorder.events.contains("copy"))
        XCTAssertFalse(recorder.events.contains("write"))
        XCTAssertFalse(recorder.events.contains("restore"))
    }

    /// The snapshot is still taken. Pasting back goes through the clipboard,
    /// and putting an empty snapshot back afterwards would wipe what somebody
    /// had in it.
    func testTheClipboardIsStillRememberedForThePasteThatFollows() async {
        reader.selection = "выделенный текст"

        _ = await makeCapture().capture()

        XCTAssertTrue(recorder.events.contains("snapshot"))
    }

    func testAnAppThatSaysNothingIsCopiedFromInstead() async {
        reader.selection = nil

        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .captured("что скопировалось"))
        XCTAssertTrue(result.touchedClipboard)
        XCTAssertTrue(recorder.events.contains("copy"))
    }

    /// An empty answer is indistinguishable from an app that does not support
    /// this at all, so it cannot be trusted to mean "nothing is selected":
    /// that verdict belongs to the change count.
    func testAnEmptyAnswerIsCopiedFromInstead() async {
        reader.selection = "   \n "

        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .captured("что скопировалось"))
        XCTAssertTrue(recorder.events.contains("copy"))
    }

    /// The switch exists because an app can answer with something other than
    /// the selection — the whole field, or what was selected a moment ago —
    /// and correcting the wrong text is worse than touching the clipboard.
    func testTheSystemIsNotAskedAtAllWhenTheSwitchIsOff() async {
        reader.selection = "выделенный текст"

        let result = await makeCapture().capture(readingDirectly: false)

        XCTAssertEqual(reader.asked, 0)
        XCTAssertEqual(result.outcome, .captured("что скопировалось"))
        XCTAssertTrue(result.touchedClipboard)
    }

    /// A round that copied has to say so, or the paths that put the clipboard
    /// back would stop doing it.
    func testACopiedSelectionSaysTheClipboardWasTouched() async {
        reader.selection = nil

        let result = await makeCapture().capture()

        XCTAssertTrue(result.touchedClipboard)
    }
}

@MainActor
final class FakeSelectionReader: SelectionReading {
    private let recorder: Recorder
    var selection: String?
    private(set) var asked = 0

    init(recorder: Recorder) { self.recorder = recorder }

    func selectedText() -> String? {
        asked += 1
        recorder.record("read")
        return selection
    }
}
