import SwiftUI

extension WordDiff.Result {
    /// The answer as one piece of text with the touched words tinted.
    ///
    /// Green, the way a diff has always shown what was added, and a tint rather
    /// than coloured letters: the words are still the person's words and have
    /// to read normally, since the panel is the last place text is inspected
    /// before it goes into somebody else's document. The system green is used
    /// rather than a fixed one so the marks follow the appearance — the app
    /// repaints its open windows when the theme changes.
    var highlighted: AttributedString {
        pieces.reduce(into: AttributedString()) { result, piece in
            var run = AttributedString(piece.text)
            if piece.isChanged { run.backgroundColor = Self.tint }
            result += run
        }
    }

    private static let tint = Color.green.opacity(0.28)
}
