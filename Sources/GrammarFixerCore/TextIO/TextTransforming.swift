import Foundation

/// Что делают с захваченным текстом между захватом и вставкой. Отдельный шов
/// ровно затем, чтобы тикет 04 заменил одну подстановку, а не трогал круг.
@MainActor
public protocol TextTransforming {
    /// Бросает `UserFacingError`: у отказа модели обязан быть текст для
    /// человека. Молчание здесь означало бы, что выделение исчезло в никуда.
    func transform(_ text: String) async throws -> String
}

/// Заглушка вместо модели: верхний регистр видно глазами, и круг проверяется
/// руками без сети, ключа и денег. Оставлена намеренно — когда круг и модель
/// расходятся в поведении, подмена одной строки в AppDelegate показывает, чья
/// это половина.
public struct UppercasePlaceholder: TextTransforming {
    public init() {}

    public func transform(_ text: String) async -> String { text.uppercased() }
}
