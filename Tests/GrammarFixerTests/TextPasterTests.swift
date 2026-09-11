import AppKit
import XCTest
@testable import GrammarFixerCore

/// What is checked about pasting is the order, not the fact: restoring the
/// clipboard before the target app has read it means pasting whatever the
/// clipboard held beforehand into somebody's document.
@MainActor
final class TextPasterTests: XCTestCase {
    private var recorder: Recorder!
    private var clipboard: FakeClipboard!
    private var keyboard: FakeKeyboard!
    private var focus: FakeFocusRestorer!
    private var clock: FakeClock!

    private let snapshot = ClipboardSnapshot(items: [.init(payloads: ["public.utf8-plain-text": Data("what was there".utf8)])])

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

        XCTAssertEqual(clock.ticks, 1, "there has to be a pause between pasting and restoring")
    }

    func testRestoreIsSkippedWhenTheSettingIsOff() async {
        _ = await paste(method: .clipboard, restoreClipboard: false)

        XCTAssertEqual(recorder.events, ["write", "activate", "paste"])
        XCTAssertNil(clipboard.restored)
    }

    /// Typing does not touch the clipboard at all, so it can be put back at
    /// once and the invented delay disappears from the round.
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

    /// If focus did not come back, nothing may be pasted: the text would land
    /// in the wrong window.
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
