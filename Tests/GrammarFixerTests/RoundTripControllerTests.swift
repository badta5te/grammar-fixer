import AppKit
import XCTest
@testable import GrammarFixerCore

/// Круг целиком. Проверяется не то, что он работает, а то, что каждая ветка
/// выхода чем-то заканчивается: тихий отказ здесь значит, что человек ждёт
/// замены выделения, которой не будет.
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

        // Захват удаётся: с третьего тика опроса счётчик буфера сдвигается.
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

    /// Ждёт, пока круг дойдёт до конца: он живёт в отдельной задаче.
    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    func testFixedTextIsPastedBack() async {
        transform.answer = .success("Выделенный текст.")
        makeController().run()
        await settle()

        XCTAssertEqual(transform.received, ["выделенный текст"])
        // Порядок и есть то, что ломается незаметно: вернуть снимок раньше
        // вставки значит вставить в чужой документ прежнее содержимое буфера.
        XCTAssertEqual(
            recorder.events.filter { ["transform", "write", "paste", "restore"].contains($0) },
            ["transform", "write", "paste", "restore"]
        )
        XCTAssertEqual(clipboard.restored?.items.count, 1)
        XCTAssertTrue(notices.shown.isEmpty)
    }

    /// Главное новое место тикета. К моменту отказа модели выделение человека
    /// уже лежит в буфере обмена вместо того, что там было: захват положил его
    /// туда. Без возврата отказ сети тихо съедает буфер.
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

    /// Круг с моделью длится секунды, а не миллисекунды. Второе нажатие в это
    /// время человек делает именно потому, что не видит результата, и оно
    /// обязано хоть чем-то ответить.
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
