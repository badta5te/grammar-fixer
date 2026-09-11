import Foundation

/// Ошибка, у которой есть текст для человека. Тихий сбой в этом приложении
/// стоит дороже обычного: человек выделил текст, нажал хоткей и ждёт замены.
/// Молчание он отличит от работы только через минуту.
public protocol UserFacingError: Error {
    var title: String { get }
    var message: String { get }
}

extension RoundTripError: UserFacingError {}

/// Сообщение, у которого нет своего типа ошибки: разовые случаи вроде «журнала
/// ещё нет». Заводить ради них перечисление незачем.
public struct Notice: UserFacingError {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}
