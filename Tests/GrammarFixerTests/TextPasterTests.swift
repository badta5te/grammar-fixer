import AppKit
import XCTest
@testable import GrammarFixerCore

/// У вставки проверяется порядок, а не факт: восстановить буфер раньше, чем
/// целевое приложение его прочитало, значит вставить в чужой документ то, что
/// лежало в буфере до вызова.
@MainActor
final class TextPasterTests: XCTestCase {
    private var recorder: Recorder!
    private var clipboard: FakeClipboard!
    private var keyboard: FakeKeyboard!
    private var focus: FakeFocusRestorer!
    private var clock: FakeClock!

    private let snapshot = ClipboardSnapshot(items: [.init(payloads: ["public.utf8-plain-text": Data("было".utf8)])])

    override func setUp() async throws {
        recorder = Recorder()
        clipboard = FakeClipboard(recorder: recorder)
        keyboard = FakeKeyboard(recorder: recorder)
        focus = FakeFocusRestorer(recorder: recorder)
        clock = FakeClock()
    }

    private func makePaster() -> TextPaster {
        TextPaster(
            clipboard: clipboard,
            keyboard: keyboard,
            focus: focus,
            sleep: { [clock] in await clock!.sleep($0) }
        )
    }

    private func paste(method: PasteMethod, restoreClipboard: Bool) async -> Result<Void, RoundTripError> {
        await makePaster().paste(
            "исправленный текст",
            into: .current,
            method: method,
            restoreClipboard: restoreClipboard,
            snapshot: snapshot
        )
    }

    func testClipboardPasteWritesActivatesPastesThenRestores() async {
        let result = await paste(method: .clipboard, restoreClipboard: true)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(recorder.events, ["write", "activate", "paste", "restore"])
        XCTAssertEqual(clipboard.restored, snapshot)
    }

    func testClipboardPasteWaitsBeforeRestoringSoTheTargetCanRead() async {
        _ = await paste(method: .clipboard, restoreClipboard: true)

        XCTAssertEqual(clock.ticks, 1, "между вставкой и восстановлением должна быть пауза")
    }

    func testRestoreIsSkippedWhenTheSettingIsOff() async {
        _ = await paste(method: .clipboard, restoreClipboard: false)

        XCTAssertEqual(recorder.events, ["write", "activate", "paste"])
        XCTAssertNil(clipboard.restored)
    }

    /// Набор текста не трогает буфер вовсе, поэтому его можно вернуть сразу и
    /// выдуманная задержка исчезает из круга.
    func testTypingRestoresImmediatelyAndNeverTouchesTheClipboardContents() async {
        let result = await paste(method: .typing, restoreClipboard: true)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(recorder.events, ["restore", "activate", "type"])
        XCTAssertEqual(keyboard.typed, "исправленный текст")
        XCTAssertEqual(clock.ticks, 0)
    }

    func testTypingWithRestoreOffStillNeverWritesToTheClipboard() async {
        _ = await paste(method: .typing, restoreClipboard: false)

        XCTAssertEqual(recorder.events, ["activate", "type"])
    }

    /// Если фокус не вернулся, вставлять нельзя: текст уедет не в то окно.
    func testPasteIsAbandonedWhenFocusDoesNotReturn() async {
        focus.confirms = false

        let result = await paste(method: .clipboard, restoreClipboard: true)

        XCTAssertEqual(result.failure, .focusLost)
        XCTAssertEqual(recorder.events, ["write", "activate", "restore"])
    }

    func testTypingIsAlsoAbandonedWhenFocusDoesNotReturn() async {
        focus.confirms = false

        let result = await paste(method: .typing, restoreClipboard: true)

        XCTAssertEqual(result.failure, .focusLost)
        XCTAssertNil(keyboard.typed)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
