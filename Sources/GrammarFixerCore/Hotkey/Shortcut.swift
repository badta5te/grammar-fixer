import AppKit
import Carbon.HIToolbox

/// A key combination, as a value.
///
/// The key is a code rather than a character on purpose. Carbon registers a
/// physical key, and a character would mean something different the moment the
/// keyboard layout changes: the key that types `g` on a Latin layout types `п`
/// on a Russian one, and the shortcut has to be the same key either way. For
/// the same reason the name shown on screen comes from a table of Latin labels
/// rather than from the layout in force — a combination that renamed itself
/// halfway through a working day would be unrecognizable.
public struct Shortcut: Equatable, Hashable, Sendable {
    /// The four modifiers somebody can put in a shortcut. Not
    /// `NSEvent.ModifierFlags`: that carries Caps Lock, the function bit and
    /// left-versus-right, none of which belong in a stored combination.
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// The modifiers that make a global shortcut safe to hold. Shift alone
        /// is not one of them: shift plus a letter is a capital letter.
        static let real: Modifiers = [.control, .option, .command]

        public init(_ flags: NSEvent.ModifierFlags) {
            var modifiers: Modifiers = []
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            self = modifiers
        }

        public var flags: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.control) { flags.insert(.control) }
            if contains(.option) { flags.insert(.option) }
            if contains(.shift) { flags.insert(.shift) }
            if contains(.command) { flags.insert(.command) }
            return flags
        }

        var carbon: UInt32 {
            var mask = 0
            if contains(.control) { mask |= controlKey }
            if contains(.option) { mask |= optionKey }
            if contains(.shift) { mask |= shiftKey }
            if contains(.command) { mask |= cmdKey }
            return UInt32(mask)
        }

        /// The order macOS uses in its own menus, so a shortcut written here
        /// reads like a shortcut written anywhere else on the system.
        public var display: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A combination as it was pressed.
    public init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: Modifiers(event.modifierFlags))
    }

    /// What the app ships with: every modifier at once, on a letter nothing
    /// else uses. It suits one person and is not obliged to suit anybody else,
    /// which is the reason the editor exists.
    public static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_G),
        modifiers: [.command, .control, .option, .shift]
    )

    public var carbonModifiers: UInt32 { modifiers.carbon }

    public var display: String { modifiers.display + keyName }

    public var keyName: String { Self.names[keyCode] ?? "Key \(keyCode)" }

    /// The same combination for an `NSMenuItem`, which wants a character
    /// rather than a key code. A key with no single character of its own gets
    /// none: a menu item without a key equivalent shows nothing, which is
    /// better than showing the wrong letter.
    public var menuKeyEquivalent: String {
        if keyCode == UInt32(kVK_Space) { return " " }
        let name = keyName
        guard name.count == 1, name.first?.isLetter == true || name.first?.isNumber == true else {
            return ""
        }
        return name.lowercased()
    }

    public var menuModifiers: NSEvent.ModifierFlags { modifiers.flags }

    /// The Latin label for each key this app can name. Everything missing from
    /// here still works and shows its key code.
    private static let names: [UInt32: String] = {
        var names: [UInt32: String] = [:]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
            (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Escape, "⎋"),
            (kVK_Delete, "⌫"), (kVK_ForwardDelete, "⌦"), (kVK_ANSI_KeypadEnter, "⌤"),
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_Home, "↖"), (kVK_End, "↘"), (kVK_PageUp, "⇞"), (kVK_PageDown, "⇟"),
            (kVK_Help, "Help"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"),
            (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"),
            (kVK_F11, "F11"), (kVK_F12, "F12"), (kVK_F13, "F13"), (kVK_F14, "F14"),
            (kVK_F15, "F15"), (kVK_F16, "F16"), (kVK_F17, "F17"), (kVK_F18, "F18"),
            (kVK_F19, "F19"), (kVK_F20, "F20"),
        ]
        for (code, name) in letters { names[UInt32(code)] = name }
        return names
    }()
}
