import XCTest
@testable import GrammarFixerCore

/// Every word the app shows a person is English. A stray Russian string is
/// easy to leave behind, so a test watches the boundary.
final class RoundTripErrorTests: XCTestCase {
    func testEveryErrorHasSomethingToShowTheUser() {
        for error in RoundTripError.allCases {
            XCTAssertFalse(error.title.isEmpty, "\(error) has no title")
            XCTAssertFalse(error.message.isEmpty, "\(error) has no explanation")
        }
    }

    func testUserFacingTextIsEnglish() {
        let cyrillic = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        for error in RoundTripError.allCases {
            for text in [error.title, error.message] {
                XCTAssertNil(text.rangeOfCharacter(from: cyrillic), "Russian text in the interface: \(text)")
            }
        }
    }

    /// A message has to name the cause, not merely the refusal: "nothing
    /// happened" is exactly the silent failure the ticket exists to remove.
    func testTheSecureInputErrorNamesTheCause() {
        XCTAssertTrue(RoundTripError.secureInputActive.message.lowercased().contains("secure input"))
    }
}

/// Failures on the way to the model are shown the same way and obey the same
/// rule about the language of the interface.
final class LLMErrorTests: XCTestCase {
    private let all: [LLMError] = [
        .notConfigured,
        .noKey,
        .noModel,
        .badAddress("localhost:1234"),
        .unknownProvider("madeup"),
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
            XCTAssertFalse(error.title.isEmpty, "\(error) has no title")
            XCTAssertFalse(error.message.isEmpty, "\(error) has no explanation")
        }
    }

    func testUserFacingTextIsEnglish() {
        let cyrillic = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        for error in all {
            for text in [error.title, error.message] {
                XCTAssertNil(text.rangeOfCharacter(from: cyrillic), "Russian text in the interface: \(text)")
            }
        }
    }

    /// Providers echo the key they were sent back in an error description, and
    /// the description is shown on screen: in an open window, over a shoulder,
    /// during a screen share. The key is cut out of that text.
    func testTheKeyIsCutOutOfTheProviderDescription() {
        let leak = LLMError.unauthorized("Incorrect API key provided: sk-proj-A1b2C3d4E5f6G7h8I9j0K1l2")
        XCTAssertFalse(leak.message.contains("sk-proj-A1b2C3d4E5f6G7h8I9j0K1l2"))
        XCTAssertTrue(leak.message.contains("Incorrect API key provided"))
    }

    /// A key also arrives with no spaces around it: in quotes, after an equals
    /// sign, in brackets. So a word boundary here is wider than a space.
    func testTheKeyIsCutOutEvenWithoutSpacesAroundIt() {
        let leak = LLMError.providerRejected(#"Invalid value for "api_key"="sk-abcdefghijklmnopqrstuvwx""#)
        XCTAssertFalse(leak.message.contains("sk-abcdefghijklmnopqrstuvwx"))
        XCTAssertTrue(leak.message.contains("api_key"))
    }

    func testAnOrdinaryDescriptionSurvivesWhole() {
        let error = LLMError.providerRejected("Model gpt-4o-mini-2024-07-18 does not exist")
        XCTAssertTrue(error.message.contains("Model gpt-4o-mini-2024-07-18 does not exist"))
    }

    /// A blocked plain-HTTP address is not a lost connection. Calling it one
    /// sends the person to their Wi-Fi instead of their configuration file.
    func testAnUnknownUrlFailureIsNotCalledALostConnection() {
        let blocked = URLError(.appTransportSecurityRequiresSecureConnection)
        guard case .unexpected = LLMError.from(blocked) else {
            return XCTFail("expected the catch-all failure, got \(LLMError.from(blocked))")
        }
        XCTAssertEqual(LLMError.from(URLError(.notConnectedToInternet)), .noConnection)
    }

    func testAFailedRoundSaysTheTextWasLeftAlone() {
        for error in [LLMError.noConnection, .timedOut, .emptyAnswer] {
            XCTAssertTrue(
                error.message.lowercased().contains("untouched"),
                "\(error) does not say the text is still intact"
            )
        }
    }
}
