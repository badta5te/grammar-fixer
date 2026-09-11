import Foundation

/// Tokens guessed from the text, for the rounds where the provider reported
/// none.
///
/// Every preset in this app does report usage, so this path is narrow. It is
/// not optional though: the request for usage is a flag that can be off, one
/// OpenAI-compatible server in ten refuses the request outright and gets
/// retried without it, and a local server may report nothing at all. Without a
/// guess those rounds would cost nothing on the counter, which is the one
/// reading that is certainly wrong.
///
/// The result is a lower bound and is marked as an estimate wherever it is
/// shown. It is not a tokenizer and is not trying to be one.
public enum TokenEstimate {
    /// Latin text runs at roughly four characters to a token in the common
    /// tokenizers.
    private static let latinCharactersPerToken = 4.0

    /// Cyrillic is split far more finely — two to three characters a token —
    /// because the vocabularies these models were built with are mostly
    /// English. Using the Latin divisor on Russian understates a round by
    /// about a third, and a counter that drifts low all month is worse than no
    /// counter.
    private static let cyrillicCharactersPerToken = 2.5

    public static func tokens(in text: String) -> Int {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return 0 }

        let divisor = isMostlyCyrillic(trimmed) ? cyrillicCharactersPerToken : latinCharactersPerToken
        // At least one: a short round that rounds down to nothing would make a
        // month of short rounds read as free.
        return max(1, Int((Double(trimmed.count) / divisor).rounded()))
    }

    /// A Russian sentence with a few Latin words in it is still Russian, so
    /// the question is which script the letters mostly belong to rather than
    /// whether any Cyrillic appears at all.
    private static func isMostlyCyrillic(_ text: String) -> Bool {
        var cyrillic = 0
        var letters = 0
        for character in text where character.isLetter {
            letters += 1
            if character.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
                cyrillic += 1
            }
        }
        guard letters > 0 else { return false }
        return cyrillic * 2 > letters
    }
}
