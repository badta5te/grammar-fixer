import AppKit
import XCTest
@testable import GrammarFixerCore

/// Общий журнал вызовов. Порядок операций в круге — это и есть то, что может
/// сломаться незаметно: восстановить буфер раньше, чем целевое приложение его
/// прочитало, значит вставить в чужой документ прошлое содержимое буфера.
@MainActor
final class Recorder {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

@MainActor
final class FakeClipboard: Clipboard {
    let recorder: Recorder
    var changeCount = 1
    var text: String?
    var restored: ClipboardSnapshot?
    var snapshotToReturn: ClipboardSnapshot

    init(recorder: Recorder, snapshot: ClipboardSnapshot = ClipboardSnapshot(items: [])) {
        self.recorder = recorder
        self.snapshotToReturn = snapshot
    }

    /// Имитирует доставку синтетического ⌘C: счётчик сдвинулся, текст появился.
    func simulateCopy(_ copied: String?) {
        changeCount += 1
        text = copied
    }

    func readText() -> String? { text }

    func snapshot() -> ClipboardSnapshot {
        recorder.record("snapshot")
        return snapshotToReturn
    }

    @discardableResult
    func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        recorder.record("restore")
        restored = snapshot
        return true
    }

    func write(_ value: String) {
        recorder.record("write")
        text = value
        changeCount += 1
    }
}

@MainActor
final class FakeKeyboard: SyntheticKeyboard {
    let recorder: Recorder
    var typed: String?

    init(recorder: Recorder) { self.recorder = recorder }

    func copy() { recorder.record("copy") }
    func paste() { recorder.record("paste") }
    func type(_ text: String) {
        recorder.record("type")
        typed = text
    }
}

@MainActor
final class FakeFocusRestorer: FocusRestoring {
    let recorder: Recorder
    var confirms: Bool

    init(recorder: Recorder, confirms: Bool = true) {
        self.recorder = recorder
        self.confirms = confirms
    }

    func activate(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        recorder.record("activate")
        return confirms
    }
}

/// Счётчик тиков вместо часов: тесты не должны зависеть от настоящего времени.
@MainActor
final class FakeClock {
    private(set) var ticks = 0
    var onTick: (Int) -> Void = { _ in }

    func sleep(_ interval: TimeInterval) async {
        ticks += 1
        onTick(ticks)
    }
}

@MainActor
final class FakeEnvironment: RoundTripEnvironment {
    private let recorder: Recorder
    var isAccessibilityTrusted = true
    var isSecureInputActive = false
    var frontmostApplication: NSRunningApplication? = .current
    private(set) var beeps = 0

    init(recorder: Recorder) { self.recorder = recorder }

    func beep() {
        recorder.record("beep")
        beeps += 1
    }
}

@MainActor
final class FakeNotices: NoticePresenting {
    private(set) var shown: [any UserFacingError] = []

    func show(_ error: any UserFacingError) { shown.append(error) }
}

/// Модель, которую можно задержать. Круг с настоящей моделью длится секунды, и
/// проверять поведение во время ожидания нужно именно так.
@MainActor
final class FakeTransform: TextTransforming {
    private let recorder: Recorder
    var answer: Swift.Result<String, any Error> = .success("исправлено")
    var waitsForRelease = false
    private(set) var received: [String] = []
    private var gate: CheckedContinuation<Void, Never>?

    init(recorder: Recorder) { self.recorder = recorder }

    func transform(_ text: String) async throws -> String {
        recorder.record("transform")
        received.append(text)
        if waitsForRelease {
            await withCheckedContinuation { gate = $0 }
        }
        return try answer.get()
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}
