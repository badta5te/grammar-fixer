import XCTest
@testable import GrammarFixerCore

/// Весь интерфейс приложения на английском. Комментарии и документация — на
/// русском, и перепутать эти два правила легко, поэтому за границей следит тест.
final class RoundTripErrorTests: XCTestCase {
    func testEveryErrorHasSomethingToShowTheUser() {
        for error in RoundTripError.allCases {
            XCTAssertFalse(error.title.isEmpty, "\(error) без заголовка")
            XCTAssertFalse(error.message.isEmpty, "\(error) без пояснения")
        }
    }

    func testUserFacingTextIsEnglish() {
        let cyrillic = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        for error in RoundTripError.allCases {
            for text in [error.title, error.message] {
                XCTAssertNil(text.rangeOfCharacter(from: cyrillic), "русский текст в интерфейсе: \(text)")
            }
        }
    }

    /// Сообщение должно называть причину, а не только факт отказа: «ничего не
    /// произошло» — это ровно тот тихий сбой, который тикет обязан устранить.
    func testTheSecureInputErrorNamesTheCause() {
        XCTAssertTrue(RoundTripError.secureInputActive.message.lowercased().contains("secure input"))
    }
}
