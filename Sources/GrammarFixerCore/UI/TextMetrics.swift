import Foundation

/// The counters in the footer. Words are counted the way a person would count
/// them rather than the way a tokenizer does: the number next to the text has
/// to match what is on screen.
public enum TextMetrics {
    public static func characters(in text: String) -> Int { text.count }

    public static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// How many places the model touched, for the footer beside the counters.
    /// "No changes" is a real and reassuring answer, so it is spelled out
    /// rather than shown as a zero.
    public static func describeChanges(_ count: Int) -> String {
        guard count > 0 else { return "no changes" }
        return "\(count) \(count == 1 ? "change" : "changes")"
    }

    /// "128 characters · 21 words", with the singular kept: a footer that says
    /// "1 words" reads as a bug in everything else too.
    public static func describe(_ text: String) -> String {
        let characters = characters(in: text)
        let words = words(in: text)
        return "\(characters) \(characters == 1 ? "character" : "characters")"
            + " · \(words) \(words == 1 ? "word" : "words")"
    }
}
