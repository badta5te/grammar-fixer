import Foundation

/// Промпт хранится одним куском и не разрезается на системную и
/// пользовательскую части. Разрезание теряет завершающий якорь `Rewritten
/// text:`, а якорь делает настоящую работу: он подавляет «Here is the
/// corrected text:» у слабых моделей ещё до всякой санитизации.
public struct Prompt: Sendable {
    public static let placeholder = "{selection}"

    public let template: String

    public init(template: String) {
        self.template = template
    }

    /// Тот же промпт, что работал в Raycast. Менять его без нужды не стоит:
    /// формулировки здесь проверены на настоящих текстах, а не подобраны.
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
