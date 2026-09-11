import AppKit
import Carbon.HIToolbox
import XCTest
@testable import GrammarFixerCore

/// The combination as a value: what it is called on screen, what Carbon is
/// told, and what a recorded keypress turns into.
final class ShortcutTests: XCTestCase {
    func testTheDefaultIsTheOneTheAppShipsWith() {
        XCTAssertEqual(Shortcut.default.keyCode, UInt32(kVK_ANSI_G))
        XCTAssertEqual(Shortcut.default.modifiers, [.command, .control, .option, .shift])
    }

    /// The order is the one macOS uses in its own menus, so a shortcut written
    /// here reads the same as a shortcut written anywhere else on the system.
    func testTheNameIsWrittenTheWayAMenuWritesIt() {
        XCTAssertEqual(Shortcut.default.display, "⌃⌥⇧⌘G")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command]).display, "⌘K")
        XCTAssertEqual(
            Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .option]).display,
            "⌃⌥Space"
        )
    }

    func testCarbonIsToldTheSameCombination() {
        XCTAssertEqual(
            Shortcut.default.carbonModifiers,
            UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(Shortcut(keyCode: 0, modifiers: [.option]).carbonModifiers, UInt32(optionKey))
    }

    /// Keys with no letter of their own still need a name, or the window would
    /// show a number nobody can match to the key they pressed.
    func testKeysWithoutALetterAreStillNamed() {
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_F5), modifiers: [.command]).display, "⌘F5")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: [.command]).display, "⌘←")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_Return), modifiers: [.command]).display, "⌘↩")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_ANSI_Slash), modifiers: [.command]).display, "⌘/")
    }

    /// A key this app has no name for must not stop it working: the
    /// combination still registers, and the window says which key it was.
    func testAKeyWithNoNameOfItsOwnFallsBackToItsNumber() {
        XCTAssertEqual(Shortcut(keyCode: 250, modifiers: [.command]).display, "⌘Key 250")
    }

    /// Caps Lock is not a modifier somebody can choose, and a combination
    /// recorded with it on would otherwise be stored as a different one.
    func testCapsLockAndTheFunctionKeyAreNotPartOfTheCombination() {
        let recorded = Shortcut.Modifiers(
            [.command, .shift, .capsLock, .function, .numericPad]
        )

        XCTAssertEqual(recorded, [.command, .shift])
    }

    func testTheModifiersComeBackAsSystemFlags() {
        XCTAssertEqual(
            Shortcut.Modifiers([.command, .control]).flags,
            [.command, .control]
        )
    }

    /// The menu carries the same shortcut beside "Fix Selection", and a menu
    /// item wants a character rather than a key code.
    func testTheMenuGetsTheSameCombination() {
        XCTAssertEqual(Shortcut.default.menuKeyEquivalent, "g")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command]).menuKeyEquivalent, " ")
        // Nothing rather than a wrong letter: a menu item with no key
        // equivalent simply shows none.
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_F5), modifiers: [.command]).menuKeyEquivalent, "")
    }
}

/// Where the combination is kept between launches.
@MainActor
final class ShortcutSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAFirstLaunchGetsTheShippedCombination() {
        XCTAssertEqual(Settings(defaults: defaults).shortcut, .default)
    }

    func testANewCombinationSurvivesARestart() {
        let chosen = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .option])
        Settings(defaults: defaults).shortcut = chosen

        XCTAssertEqual(Settings(defaults: defaults).shortcut, chosen)
    }

    /// The keys can be written by hand from a terminal, and a combination with
    /// no modifiers in it would fire in the middle of a word.
    func testACombinationWithNoModifiersIsIgnored() {
        let settings = Settings(defaults: defaults)
        defaults.set(Int(kVK_ANSI_J), forKey: Settings.shortcutKeyCodeKey)
        defaults.set(0, forKey: Settings.shortcutModifiersKey)

        XCTAssertEqual(settings.shortcut, .default)
    }

    func testNonsenseInTheModifiersIsIgnored() {
        let settings = Settings(defaults: defaults)
        defaults.set("щ", forKey: Settings.shortcutModifiersKey)

        XCTAssertEqual(settings.shortcut, .default)
    }
}

/// What macOS already owns. Carbon answers noErr for a combination another app
/// holds, so the only way to refuse one before it silently stops working is to
/// read what the system says about its own shortcuts.
final class SystemShortcutsTests: XCTestCase {
    /// Spotlight, as the system's own defaults record it: the second parameter
    /// is the key code and the third the modifier mask.
    private let spotlight: [String: Any] = [
        "64": [
            "enabled": true,
            "value": ["type": "standard", "parameters": [32, kVK_Space, 1_048_576]],
        ],
    ]

    func testAnEnabledSystemShortcutIsFound() {
        XCTAssertEqual(
            SystemShortcuts.parse(spotlight),
            [Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command])]
        )
    }

    func testAShortcutTheSystemHasTurnedOffIsFree() {
        let plist: [String: Any] = [
            "64": [
                "enabled": false,
                "value": ["type": "standard", "parameters": [32, kVK_Space, 1_048_576]],
            ],
        ]

        XCTAssertTrue(SystemShortcuts.parse(plist).isEmpty)
    }

    /// Some entries hold no key at all: 65535 is the system's way of saying
    /// "nothing", and a shortcut on a key that does not exist would refuse a
    /// combination nobody is using.
    func testAnEntryWithNoKeyIsSkipped() {
        let plist: [String: Any] = [
            "13": ["enabled": true, "value": ["parameters": [65_535, 65_535, 1_048_576]]],
        ]

        XCTAssertTrue(SystemShortcuts.parse(plist).isEmpty)
    }

    func testAnEntryThatMakesNoSenseIsSkipped() {
        let plist: [String: Any] = [
            "1": ["enabled": true, "value": ["parameters": [32]]],
            "2": ["enabled": true],
            "3": "not a dictionary",
        ]

        XCTAssertTrue(SystemShortcuts.parse(plist).isEmpty)
    }

    /// The mask carries bits that are not modifiers anybody can press, and
    /// numbers arrive from a plist as whatever they were written as.
    func testBitsThatAreNotModifiersAreDropped() {
        let plist: [String: Any] = [
            "7": [
                "enabled": true,
                // Command plus the function-key bit, written as a real number.
                "value": ["parameters": [32.0, Double(kVK_Space), 9_437_184.0]],
            ],
        ]

        XCTAssertEqual(
            SystemShortcuts.parse(plist),
            [Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command])]
        )
    }
}

/// Whether a combination can be had at all. Three different refusals, and the
/// person is told which.
@MainActor
final class ShortcutCheckTests: XCTestCase {
    func testTheShippedCombinationIsFree() {
        XCTAssertNil(ShortcutCheck.run(.default, takenBy: []))
    }

    /// A bare letter, or a letter with only shift, is typing.
    func testACombinationWithoutARealModifierIsRefused() {
        XCTAssertEqual(ShortcutCheck.run(Shortcut(keyCode: 0, modifiers: []), takenBy: []), .noModifiers)
        XCTAssertEqual(
            ShortcutCheck.run(Shortcut(keyCode: 0, modifiers: [.shift]), takenBy: []),
            .noModifiers
        )
    }

    func testACombinationTheSystemOwnsIsRefused() {
        let spotlight = Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command])

        XCTAssertEqual(ShortcutCheck.run(spotlight, takenBy: [spotlight]), .takenByTheSystem)
    }

    /// Every refusal has to name the combination and say what to do next: a
    /// shortcut that silently does not work later is the whole reason this
    /// check exists.
    func testEveryRefusalSaysWhichCombinationAndWhatToDo() {
        for refusal in ShortcutRefusal.allCases {
            let notice = refusal.notice(for: .default)
            XCTAssertTrue(notice.title.contains("⌃⌥⇧⌘G") || notice.message.contains("⌃⌥⇧⌘G"))
            XCTAssertFalse(notice.title.isEmpty)
            XCTAssertFalse(notice.message.isEmpty)
        }
    }
}
