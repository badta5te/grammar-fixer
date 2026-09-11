import Foundation

/// Вырезание ключей из чужого текста.
///
/// Провайдеры отражают присланный ключ в описании ошибки, а описание уходит
/// человеку на экран. Экран бывает общим: демонстрация, сосед, скриншот в чат
/// с вопросом «что это значит». Поэтому ключ вырезается до показа, а не после
/// первого случая.
enum Redaction {
    private static let prefixes = ["sk-", "sk_", "pk-", "pk_", "gsk_", "xai-", "api-", "key-", "Bearer "]

    /// Ключ без узнаваемого начала опознаётся по длине: осмысленных слов такой
    /// длины в описаниях ошибок не бывает.
    private static let opaqueLength = 32

    static func withoutKeys(_ text: String) -> String {
        text
            .components(separatedBy: " ")
            .map(hide)
            .joined(separator: " ")
    }

    private static func hide(_ word: String) -> String {
        // Хвостовая пунктуация к ключу не относится и остаётся на месте.
        let trailing = word.suffix(while: { ".,;:!?)\"'".contains($0) })
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
