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

/// Отказы на пути к модели показываются тем же способом и подчиняются тому же
/// правилу про язык интерфейса.
final class LLMErrorTests: XCTestCase {
    private let all: [LLMError] = [
        .noConfiguration(path: "~/c.json"),
        .brokenConfiguration(path: "~/c.json", reason: "bad"),
        .noKey(path: "~/c.json"),
        .noConnection,
        .timedOut,
        .unauthorized("Incorrect API key"),
        .rateLimited(nil),
        .providerRejected("model not found"),
        .providerUnavailable(status: 503, detail: nil),
        .emptyAnswer,
    ]

    func testEveryFailureHasSomethingToShowTheUser() {
        for error in all {
            XCTAssertFalse(error.title.isEmpty, "\(error) без заголовка")
            XCTAssertFalse(error.message.isEmpty, "\(error) без пояснения")
        }
    }

    func testUserFacingTextIsEnglish() {
        let cyrillic = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        for error in all {
            for text in [error.title, error.message] {
                XCTAssertNil(text.rangeOfCharacter(from: cyrillic), "русский текст в интерфейсе: \(text)")
            }
        }
    }

    /// Провайдеры отражают присланный ключ в описании ошибки, а описание
    /// показывается на экране — в открытом окне, через плечо, на демонстрации
    /// экрана. Ключ из чужого текста вырезается.
    func testTheKeyIsCutOutOfTheProviderDescription() {
        let leak = LLMError.unauthorized("Incorrect API key provided: sk-proj-A1b2C3d4E5f6G7h8I9j0K1l2")
        XCTAssertFalse(leak.message.contains("sk-proj-A1b2C3d4E5f6G7h8I9j0K1l2"))
        XCTAssertTrue(leak.message.contains("Incorrect API key provided"))
    }

    func testAnOrdinaryDescriptionSurvivesWhole() {
        let error = LLMError.providerRejected("Model gpt-4o-mini-2024-07-18 does not exist")
        XCTAssertTrue(error.message.contains("Model gpt-4o-mini-2024-07-18 does not exist"))
    }

    func testAFailedRoundSaysTheTextWasLeftAlone() {
        for error in [LLMError.noConnection, .timedOut, .emptyAnswer] {
            XCTAssertTrue(
                error.message.lowercased().contains("untouched"),
                "\(error) не говорит, что текст остался цел"
            )
        }
    }
}
