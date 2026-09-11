import AppKit
import Foundation

/// The shortcuts macOS keeps for itself.
///
/// Reading them is the only way to refuse a combination before it quietly
/// stops working: `RegisterEventHotKey` answers noErr for a combination the
/// system already owns, which the prototype found the hard way. This covers
/// the system's own keyboard shortcuts and nothing else — another app holding
/// a combination stays invisible from here, and is caught later or not at all.
public enum SystemShortcuts {
    private static let domain = "com.apple.symbolichotkeys"
    private static let key = "AppleSymbolicHotKeys"

    @MainActor
    public static var current: Set<Shortcut> {
        guard let defaults = UserDefaults(suiteName: domain),
              let hotKeys = defaults.dictionary(forKey: key)
        else {
            // Nothing readable is read as nothing taken. The alternative is
            // refusing every combination on a machine whose preferences this
            // app cannot see, which would leave the editor unusable.
            Log.write("the system's own shortcuts could not be read")
            return []
        }
        return parse(hotKeys)
    }

    /// The system writes one entry per shortcut, keyed by a number of its own:
    ///
    ///     64 = { enabled = 1; value = { parameters = (32, 49, 1048576); }; }
    ///
    /// The parameters are the character, the key code and the modifier mask,
    /// in that order.
    static func parse(_ hotKeys: [String: Any]) -> Set<Shortcut> {
        var taken: Set<Shortcut> = []
        for entry in hotKeys.values {
            guard let entry = entry as? [String: Any] else { continue }
            // A missing flag is read as enabled: the system knows about the
            // entry, and treating it as free would hand out a combination
            // that later does nothing.
            if let enabled = entry["enabled"] as? Bool, !enabled { continue }
            guard let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = integer(parameters[1]),
                  let mask = integer(parameters[2]),
                  // The system's way of saying "no key at all".
                  keyCode != 65_535, keyCode >= 0
            else { continue }

            let modifiers = Shortcut.Modifiers(NSEvent.ModifierFlags(rawValue: UInt(max(0, mask))))
            taken.insert(Shortcut(keyCode: UInt32(keyCode), modifiers: modifiers))
        }
        return taken
    }

    /// Numbers come out of a plist as whatever they were written as.
    private static func integer(_ value: Any) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as Double: return Int(number)
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }
}
