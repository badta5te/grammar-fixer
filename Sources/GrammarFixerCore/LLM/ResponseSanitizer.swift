import Foundation

/// Turning a model's answer into something that can be dropped into a person's
/// text.
///
/// The prompt forbids preambles, quotes and code fences alike, but obedience
/// costs money: an expensive model returns clean text without any sanitizing,
/// while a cheap one adds "Here is the corrected text:" and wraps the result in
/// quotes. The model that breaks is precisely the one this project exists to
/// let you choose.
///
/// Every rule looks at the original text, not only at the answer. Otherwise
/// sanitizing carries off the person's own quotes and colons, and that is no
/// longer fixing grammar but damaging text.
public enum ResponseSanitizer {
    /// Anchors the model repeats back from the prompt. They are ours, so they
    /// are recognized exactly, with no guessing from the shape of a line.
    ///
    /// The Russian entries are data, not text for a reader: a model answering
    /// in Russian writes its preamble in Russian, and this list is what
    /// recognises it. Translating them would stop them matching anything.
    private static let anchors = [
        "rewritten text:",
        "corrected text:",
        "here is the corrected text:",
        "here is the rewritten text:",
        "исправленный текст:",
        "вот исправленный текст:",
    ]

    /// Quote pairs a model wraps an answer in. The Russian and typographic
    /// ones are not here for completeness: the text is most often Russian, and
    /// the wrapping arrives in the same quotes as the text.
    private static let quotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""),
        ("'", "'"),
        ("«", "»"),
        ("“", "”"),
        ("„", "“"),
        ("„", "”"),
        ("‘", "’"),
    ]

    /// A line with a colon longer than this is almost certainly real text
    /// rather than a preamble.
    private static let preambleLineLimit = 60

    public static func clean(_ output: String, original: String) -> String {
        var text = output.trimmed
        text = withoutCodeFences(text)
        text = withoutPreamble(text, original: original)
        text = withoutWrappingQuotes(text, original: original)
        return text.trimmed
    }

    /// A fence is removed only when it wraps the whole answer. A fence inside
    /// the text is the person's own code and stays where it is.
    private static func withoutCodeFences(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 3,
              lines[0].trimmed.hasPrefix("```"),
              lines[lines.count - 1].trimmed == "```",
              !lines[1..<(lines.count - 1)].contains(where: { $0.trimmed.hasPrefix("```") })
        else { return text }
        return lines[1..<(lines.count - 1)].joined(separator: "\n").trimmed
    }

    private static func withoutPreamble(_ text: String, original: String) -> String {
        let lowercased = text.lowercased()
        for anchor in anchors where lowercased.hasPrefix(anchor) {
            let rest = String(text.dropFirst(anchor.count)).trimmed
            if !rest.isEmpty { return rest }
        }

        guard let newline = text.firstIndex(of: "\n") else { return text }
        let firstLine = String(text[text.startIndex..<newline]).trimmed
        let rest = String(text[text.index(after: newline)...]).trimmed

        guard !rest.isEmpty,
              firstLine.hasSuffix(":"),
              firstLine.count <= preambleLineLimit,
              // Whether the line belongs to the person is decided by the shape
              // of their input, not by comparing the two lines. Comparing them
              // fails the moment the model does its job: a heading of their own
              // with a typo fixed no longer matches, and their heading would be
              // deleted as if it were the model's chatter.
              !original.firstLineTrimmed.hasSuffix(":")
        else { return text }
        return rest
    }

    private static func withoutWrappingQuotes(_ text: String, original: String) -> String {
        var text = text
        // Two passes: `"«text»"` happens. More than two is not wrapping.
        for _ in 0..<2 {
            guard let stripped = removingOneQuoteLayer(text, original: original) else { return text }
            text = stripped
        }
        return text
    }

    private static func removingOneQuoteLayer(_ text: String, original: String) -> String? {
        guard text.count >= 2, let first = text.first, let last = text.last else { return nil }
        let original = original.trimmed

        for pair in quotePairs where first == pair.open && last == pair.close {
            // A quote the input starts with belongs to the person.
            guard original.first != pair.open else { continue }

            // `"hello" and "bye"` also begins and ends with a quote without
            // being wrapped: dropping the outer ones would damage the text.
            if pair.open == pair.close {
                guard text.filter({ $0 == pair.open }).count == 2 else { continue }
            } else {
                guard text.filter({ $0 == pair.open }).count == 1,
                      text.filter({ $0 == pair.close }).count == 1
                else { continue }
            }

            return String(text.dropFirst().dropLast()).trimmed
        }
        return nil
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var firstLineTrimmed: String {
        (components(separatedBy: "\n").first ?? "").trimmed
    }
}
