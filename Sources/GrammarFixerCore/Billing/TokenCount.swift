import Foundation

/// Token counts as they are shown.
///
/// Thousands are shortened because a month of corrections runs into six
/// figures, and a six-figure number in a menu is read as noise rather than as
/// a quantity. Under a thousand the exact number is shown: at that size it is
/// still worth knowing.
public enum TokenCount {
    public static func text(_ tokens: Int) -> String {
        guard tokens >= 1_000 else { return "\(tokens)" }
        let thousands = Double(tokens) / 1_000
        guard thousands >= 100 else { return String(format: "%.1fk", thousands) }
        return String(format: "%.0fk", thousands)
    }
}
