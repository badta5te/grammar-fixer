import Foundation

/// Cutting API keys out of somebody else's text.
///
/// Providers echo the key they were sent back in an error description, and the
/// description goes to a person's screen. Screens get shared: a demo, someone
/// sitting next to you, a screenshot pasted into a chat asking what this means.
/// So the key is cut out before it is shown, not after the first incident.
enum Redaction {
    private static let prefixes = ["sk-", "sk_", "pk-", "pk_", "gsk_", "xai-", "api-", "key-"]

    /// A key with no recognizable prefix is spotted by length: error
    /// descriptions do not contain meaningful words this long.
    private static let opaqueLength = 32

    /// A key also arrives with no spaces around it: `key=sk-…`, `"sk-…"`,
    /// `(sk-…)`. So a word boundary here is wider than a space.
    private static let boundaries = CharacterSet(charactersIn: " \t\n=:(),[]{}\"'")

    static func withoutKeys(_ text: String) -> String {
        var result = ""
        var word = ""
        for character in text {
            if character.unicodeScalars.allSatisfy(boundaries.contains) {
                result += hide(word) + String(character)
                word = ""
            } else {
                word.append(character)
            }
        }
        return result + hide(word)
    }

    private static func hide(_ word: String) -> String {
        // Trailing punctuation is not part of the key and stays where it is.
        let trailing = word.suffix(while: { ".;!?".contains($0) })
        let core = String(word.dropLast(trailing.count))

        let looksLikeKey = prefixes.contains { core.hasPrefix($0) && core.count > $0.count + 4 }
            || (core.count >= opaqueLength && core.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return looksLikeKey ? "…" + trailing : word
    }
}

private extension String {
    func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
