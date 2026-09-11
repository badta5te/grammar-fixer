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

    private func makeCapture(timeout: TimeInterval = 0.05, lateCopyWindow: TimeInterval = 0.1) -> TextCapture {
        TextCapture(
            clipboard: clipboard,
            keyboard: keyboard,
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
        XCTAssertNil(clipboard.restored, "до подтверждённого инкремента в буфер не пишется ничего")
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
