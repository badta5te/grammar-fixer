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

    /// Both combinations refused is the one case that ends with no shortcut at
    /// all: the new one is not to be had, and the one that was working a moment
    /// ago has been given back and cannot be taken again. The refusal shown
    /// beside the field only speaks about the new combination, so the news that
    /// the old one is gone too has to be said out loud.
    func testBothTheNewAndTheOldCombinationRefusedIsSomethingToRead() {
        let binder = makeBinder()
        binder.start()
        registrar.refuses = [chosen, .default]

        XCTAssertEqual(binder.apply(chosen), .refusedByTheSystem)

        XCTAssertEqual(registrar.liveCount, 0)
        registrar.press()
        XCTAssertEqual(rounds, 0)
        XCTAssertEqual(notices.shown.count, 1)
    }

    /// A combination recorded while it was free can be given to macOS in System
    /// Settings months later. Carbon answers noErr for one of those, so the
    /// registration succeeds and the key then quietly never fires. Reading what
    /// the system owns is the only way to say so, and launch is where it has to
    /// be read: `apply` alone covers the day it was chosen and no day after.
    func testAStoredCombinationTheSystemHasSinceTakenIsSomethingToRead() {
        settings.shortcut = chosen
        let binder = makeBinder(system: [chosen])

        binder.start()

        XCTAssertEqual(notices.shown.count, 1)
        XCTAssertTrue(notices.shown.first?.title.contains("macOS already uses") ?? false)
        // Registered all the same. What the system owns is read out of a plist
        // nobody promised us, and a misread that unregistered a working
        // shortcut would cost more than a warning nobody needed.
        XCTAssertEqual(registrar.events, ["register ⌥⌘J"])
    }

    /// Nothing fires while the field is listening. The combination reaching the
    /// round instead of the editor is the whole reason the key is given back.
    func testNoRoundStartsWhileTheFieldIsListening() {
        let binder = makeBinder()
        binder.start()

        binder.suspend()
        registrar.press()

        XCTAssertEqual(rounds, 0)
        XCTAssertEqual(registrar.liveCount, 0)
    }

    /// The key can be gone by the time it is asked for back: another app may
    /// have taken it while the window stood open. Silence there is an app whose
    /// only way in has disappeared without a word.
    func testTheKeyBeingGoneWhenItIsAskedForBackIsSomethingToRead() {
        let binder = makeBinder()
        binder.start()
        binder.suspend()
        registrar.refuses = [.default]

        binder.resume()

        XCTAssertEqual(registrar.liveCount, 0)
        XCTAssertEqual(notices.shown.count, 1)
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
    /// What the system thinks we hold right now, newest last. A registration
    /// drops out of here when it is given back, so that a press can tell one
    /// that is live from one that was live a moment ago. Without that the
    /// double a test leans on would report a working shortcut where there is
    /// none, which is the one answer worth having.
    private var live: [(id: Int, action: () -> Void)] = []
    private var registrations = 0

    /// How many hot keys are held. Never above one while the binder is doing
    /// its job, and zero is the state the binder promises never to be left in.
    var liveCount: Int { live.count }

    func register(_ shortcut: Shortcut, _ action: @escaping () -> Void) -> (any HotKeyHandle)? {
        guard !refuses.contains(shortcut) else {
            events.append("refused \(shortcut.display)")
            return nil
        }
        events.append("register \(shortcut.display)")
        registrations += 1
        live.append((registrations, action))
        return FakeHotKey(id: registrations, shortcut: shortcut, registrar: self)
    }

    /// Giving the same one back twice is not an event: a real hot key can be
    /// invalidated again without the system hearing about it.
    func letGo(_ id: Int, _ shortcut: Shortcut) {
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        live.remove(at: index)
        events.append("invalidate \(shortcut.display)")
    }

    /// Fires the registration the press would reach, and nothing at all when
    /// nothing is registered.
    func press() {
        live.last?.action()
    }
}

@MainActor
private final class FakeHotKey: HotKeyHandle {
    private let id: Int
    private let shortcut: Shortcut
    private weak var registrar: FakeHotKeyRegistrar?

    init(id: Int, shortcut: Shortcut, registrar: FakeHotKeyRegistrar) {
        self.id = id
        self.shortcut = shortcut
        self.registrar = registrar
    }

    func invalidate() { registrar?.letGo(id, shortcut) }
}
