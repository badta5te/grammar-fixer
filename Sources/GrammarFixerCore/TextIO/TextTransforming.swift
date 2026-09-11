import Foundation

/// Что делают с захваченным текстом между захватом и вставкой. Отдельный шов
/// ровно затем, чтобы тикет 04 заменил одну подстановку, а не трогал круг.
@MainActor
public protocol TextTransforming {
    func transform(_ text: String) async -> String
}

/// Заглушка вместо модели: верхний регистр видно глазами, и круг можно
/// проверить руками до того, как появится первый провайдер.
public struct UppercasePlaceholder: TextTransforming {
    public init() {}

    public func transform(_ text: String) async -> String { text.uppercased() }
}
