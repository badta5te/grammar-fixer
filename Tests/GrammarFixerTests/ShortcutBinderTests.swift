import Carbon.HIToolbox
import XCTest
@testable import GrammarFixerCore

/// The shortcut while the app runs. Changing it must take effect at once, and
/// a change that fails must never leave somebody with no shortcut at all: the
/// app has no Dock icon and no window, so the combination is the only way in.
@MainActor
final class ShortcutBinderTests: XCTestCase {
    private var registrar: FakeHotKeyRegistrar!
    private var notices: FakeNotices!
    private var settings: Settings!
    private var suiteName: String!
    private var rounds = 0

    private let chosen = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .option])

    override func setUp() async throws {
        suiteName = "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)"
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        registrar = FakeHotKeyRegistrar()
        notices = FakeNotices()
        rounds = 0
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeBinder(system: Set<Shortcut> = []) -> ShortcutBinder {
        ShortcutBinder(
            settings: settings,
            notices: notices,
            systemShortcuts: { system },
            register: { [registrar] shortcut, action in registrar!.register(shortcut, action) },
            action: { [weak self] in self?.rounds += 1 }
        )
    }

    func testTheStoredCombinationIsRegisteredAtLaunch() {
        let binder = makeBinder()
        binder.start()

        XCTAssertEqual(registrar.events, ["register ⌃⌥⇧⌘G"])
        XCTAssertEqual(binder.shortcut, .default)
    }

    /// The old registration goes before the new one is made. The other way
    /// round means asking the system for a key it still thinks we hold.
    func testTheOldCombinationIsLetGoBeforeTheNewOneIsTaken() {
        let binder = makeBinder()
        binder.start()

        XCTAssertNil(binder.apply(chosen))

        XCTAssertEqual(
            registrar.events,
            ["register ⌃⌥⇧⌘G", "invalidate ⌃⌥⇧⌘G", "register ⌥⌘J"]
        )
        XCTAssertEqual(binder.shortcut, chosen)
        XCTAssertEqual(Settings(defaults: UserDefaults(suiteName: suiteName)!).shortcut, chosen)
    }

    func testTheNewCombinationStartsARoundStraightAway() {
        let binder = makeBinder()
        binder.start()
        binder.apply(chosen)

        registrar.press()

        XCTAssertEqual(rounds, 1)
    }

    /// A combination another app holds is refused by Carbon, and the person
    /// keeps the shortcut they had rather than being left with nothing.
    func testARefusedCombinationLeavesTheOldOneWorking() {
        let binder = makeBinder()
        binder.start()
        registrar.refuses = [chosen]

        XCTAssertEqual(binder.apply(chosen), .refusedByTheSystem)

        XCTAssertEqual(binder.shortcut, .default)
        XCTAssertEqual(registrar.events.last, "register ⌃⌥⇧⌘G")
        registrar.press()
        XCTAssertEqual(rounds, 1)
    }

    /// The system's own shortcuts are checked before anything is touched:
    /// Carbon answers noErr for one of those, so the refusal has to come from
    /// reading what the system says rather than from trying.
    func testACombinationTheSystemOwnsIsNeverEvenTried() {
        let spotlight = Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command])
        let binder = makeBinder(system: [spotlight])
        binder.start()

        XCTAssertEqual(binder.apply(spotlight), .takenByTheSystem)

        XCTAssertEqual(registrar.events, ["register ⌃⌥⇧⌘G"])
        XCTAssertEqual(binder.shortcut, .default)
    }

    func testACombinationThatWouldFireWhileTypingIsRefused() {
        let binder = makeBinder()
        binder.start()

        XCTAssertEqual(
            binder.apply(Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.shift])),
            .noModifiers
        )

        XCTAssertEqual(registrar.events, ["register ⌃⌥⇧⌘G"])
    }

    /// Recording the same combination again is not a change, and re-taking the
    /// key for nothing is a moment with no shortcut at all.
    func testRecordingTheSameCombinationChangesNothing() {
        let binder = makeBinder()
        binder.start()

        XCTAssertNil(binder.apply(.default))

        XCTAssertEqual(registrar.events, ["register ⌃⌥⇧⌘G"])
    }

    /// A stored combination that cannot be registered at launch would be an
    /// app that does nothing at all, with nothing said about why.
    func testACombinationThatCannotBeRegisteredAtLaunchIsSomethingToRead() {
        registrar.refuses = [.default]
        let binder = makeBinder()

        binder.start()

        XCTAssertEqual(notices.shown.count, 1)
        XCTAssertTrue(notices.shown.first?.title.contains("⌃⌥⇧⌘G") ?? false)
    }

    /// While the editor is listening for a keypress, a registered hot key
    /// would swallow the very combination somebody is trying to record: a
    /// global hot key fires wherever the keyboard is pointing, our own window
    /// included.
    func testTheShortcutIsLetGoWhileACombinationIsBeingRecorded() {
        let binder = makeBinder()
        binder.start()

        binder.suspend()
        XCTAssertEqual(registrar.events, ["register ⌃⌥⇧⌘G", "invalidate ⌃⌥⇧⌘G"])

        binder.resume()
        XCTAssertEqual(
            registrar.events,
            ["register ⌃⌥⇧⌘G", "invalidate ⌃⌥⇧⌘G", "register ⌃⌥⇧⌘G"]
        )
        registrar.press()
        XCTAssertEqual(rounds, 1)
    }
}

/// Carbon in name only: what is under test is the order of registering and
/// letting go, not whether the system agrees.
@MainActor
final class FakeHotKeyRegistrar {
    private(set) var events: [String] = []
    /// Combinations the system will not hand over.
    var refuses: Set<Shortcut> = []
    private var actions: [() -> Void] = []

    func register(_ shortcut: Shortcut, _ action: @escaping () -> Void) -> (any HotKeyHandle)? {
        guard !refuses.contains(shortcut) else {
            events.append("refused \(shortcut.display)")
            return nil
        }
        events.append("register \(shortcut.display)")
        actions.append(action)
        return FakeHotKey(shortcut: shortcut, registrar: self)
    }

    func letGo(of shortcut: Shortcut) {
        events.append("invalidate \(shortcut.display)")
    }

    /// Fires whatever is registered now.
    func press() {
        actions.last?()
    }
}

@MainActor
private final class FakeHotKey: HotKeyHandle {
    private let shortcut: Shortcut
    private weak var registrar: FakeHotKeyRegistrar?

    init(shortcut: Shortcut, registrar: FakeHotKeyRegistrar) {
        self.shortcut = shortcut
        self.registrar = registrar
    }

    func invalidate() { registrar?.letGo(of: shortcut) }
}
