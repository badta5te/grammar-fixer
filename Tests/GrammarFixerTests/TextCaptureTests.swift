import XCTest
@testable import GrammarFixerCore

/// Захват — единственное место, где тихий сбой стоит дороже всего: если
/// принять «ничего не выделено» за успех, в чужое приложение уедет вчерашнее
/// содержимое буфера обмена.
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

    /// Ловушка из плана: без счётчика «ничего не выделено» неотличимо от успеха.
    func testNothingSelectedWhenTheChangeCountNeverMoves() async {
        let result = await makeCapture().capture()

        XCTAssertEqual(result.outcome, .nothingSelected)
        XCTAssertNil(clipboard.restored, "до подтверждённого инкремента в буфер не пишется ничего")
    }

    /// Найдено в Chrome: счётчик сдвинулся, а строки в буфере нет — выделение
    /// было не текстовым.
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

    /// Копия может прийти уже после того, как мы сдались. Тогда в буфере
    /// пользователя молча остаётся его выделение вместо того, что там было.
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
