import Foundation

/// The prompt is kept whole and never split into a system and a user half.
/// Splitting loses the closing anchor `Rewritten text:`, and the anchor does
/// real work: it suppresses "Here is the corrected text:" in weaker models
/// before any sanitizing happens.
public struct Prompt: Sendable {
    public static let placeholder = "{selection}"

    public let template: String

    public init(template: String) {
        self.template = template
    }

    /// The same prompt that worked in Raycast. Not worth changing without a
    /// reason: the wording here was proven on real texts, not guessed at.
    public static let `default` = Prompt(template: """
        Act as a spelling corrector and improver. Reply to each message only with the rewritten text

        Strictly follow these rules:
        - Correct spelling, grammar and punctuation
        - ALWAYS detect and maintain the original language of the text
        - NEVER surround the rewritten text with quotes
        - Don't replace urls with markdown links
        - Don't change emojis

        Text to rewrite:
        \(placeholder)

        Rewritten text:
        """)

    public func render(selection: String) -> String {
        template.replacingOccurrences(of: Self.placeholder, with: selection)
    }
}
