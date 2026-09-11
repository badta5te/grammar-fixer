import AppKit
import XCTest
@testable import GrammarFixerCore

/// A shared record of calls. The order of operations in the round is what can
/// break unnoticed: restoring the clipboard before the target app has read it
/// means pasting the previous clipboard into somebody's document.
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

    /// Imitates a synthetic ⌘C being delivered: the count moved, text
    /// appeared.
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

/// A tick counter instead of a clock: tests must not depend on real time.
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

/// A model that can be held in place. A round with a real model takes seconds,
/// and behaviour during that wait has to be checked exactly this way.
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

/// The panel, reduced to the one thing a test can check: a decision came back.
@MainActor
final class FakeResults: ResultPresenting {
    private let recorder: Recorder
    /// What the person does once there is something on screen. The default is
    /// ⏎, the common case.
    var decide: (CorrectionSession) -> ResultDecision = { .paste($0.result ?? "") }
    private(set) var presented: [CorrectionSession] = []

    init(recorder: Recorder) { self.recorder = recorder }

    func present(_ session: CorrectionSession) async -> ResultDecision {
        recorder.record("present")
        presented.append(session)
        // The panel waits for the model with the person watching it, and a
        // test waits the same way instead of pretending an answer is instant.
        //
        // The bound is a clock rather than a count of yields. A count would be
        // racing the test's own waiting loop, and losing that race would end
        // the round with an empty answer and no complaint — the test would pass
        // while checking nothing.
        let deadline = Date().addingTimeInterval(2)
        while session.result == nil, !session.hasFailed {
            guard Date() < deadline else {
                XCTFail("панель не дождалась ответа за 2 секунды")
                return .dismissed
            }
            await Task.yield()
        }
        return decide(session)
    }
}

/// The Keychain without the Keychain. What is under test above it is which key
/// is asked for and when, not Security.framework, which has tests of its own.
final class FakeSecrets: SecretStore, @unchecked Sendable {
    var stored: [String: String] = [:]
    /// A Keychain can refuse to answer, and that is not the same as being
    /// empty.
    var failure: (any Error)?

    func secret(for account: String) throws -> String? {
        if let failure { throw failure }
        return stored[account]
    }

    func store(_ secret: String, for account: String) throws {
        if let failure { throw failure }
        stored[account] = secret
    }

    func removeSecret(for account: String) throws {
        if let failure { throw failure }
        stored[account] = nil
    }
}

/// The provider's list of models, without the provider.
final class FakeModelListing: ModelListing, @unchecked Sendable {
    var models: [String] = []
    var failure: (any Error)?

    func models() async throws -> [String] {
        if let failure { throw failure }
        return models
    }
}
