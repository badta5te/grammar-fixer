import Foundation

/// Приведение ответа модели к тому, что можно вставить человеку в текст.
///
/// Промпт запрещает и преамбулу, и кавычки, и ограждения кода, но послушание
/// стоит денег: дорогая модель и без санитизации возвращает чистый текст, а
/// дешёвая добавляет «Вот исправленный текст:» и кавычки. Ломается ровно та
/// модель, ради свободы выбрать которую всё и затевалось.
///
/// Каждое правило смотрит на исходный текст, а не только на ответ. Иначе
/// санитизация уносит кавычки и двоеточия самого пользователя, а это уже не
/// исправление грамматики, а порча текста.
public enum ResponseSanitizer {
    /// Якоря, которые модель повторяет за промптом. Свои — значит опознаются
    /// точно, без догадок по форме строки.
    private static let anchors = [
        "rewritten text:",
        "corrected text:",
        "here is the corrected text:",
        "here is the rewritten text:",
        "исправленный текст:",
        "вот исправленный текст:",
    ]

    /// Пары кавычек, которыми модель оборачивает ответ. Русские и типографские
    /// здесь не для полноты: текст пользователя чаще всего русский, и обёртка
    /// приходит в тех же кавычках, что и текст.
    private static let quotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""),
        ("'", "'"),
        ("«", "»"),
        ("“", "”"),
        ("„", "“"),
        ("„", "”"),
        ("‘", "’"),
    ]

    /// Длиннее этого строка с двоеточием — почти наверняка настоящий текст,
    /// а не преамбула.
    private static let preambleLineLimit = 60

    public static func clean(_ output: String, original: String) -> String {
        var text = output.trimmed
        text = withoutCodeFences(text)
        text = withoutPreamble(text, original: original)
        text = withoutWrappingQuotes(text, original: original)
        return text.trimmed
    }

    /// Ограждение снимается только когда оно обнимает весь ответ. Ограждение
    /// внутри текста — это код пользователя, и он остаётся на месте.
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
              // Та же строка во входе значит, что она принадлежит пользователю.
              firstLine.lowercased() != original.firstLineTrimmed.lowercased()
        else { return text }
        return rest
    }

    private static func withoutWrappingQuotes(_ text: String, original: String) -> String {
        var text = text
        // Два прохода: встречается и «"«текст»"». Больше двух — уже не обёртка.
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
            // Кавычка, с которой начинается вход, принадлежит пользователю.
            guard original.first != pair.open else { continue }

            // «"привет" и "пока"» тоже начинается и кончается кавычкой, но
            // обёрткой не является: снятие крайних испортило бы текст.
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
