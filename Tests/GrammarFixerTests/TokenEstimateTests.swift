import XCTest
@testable import GrammarFixerCore

/// The fallback for a provider that reported no usage. It is an estimate and
/// says so; what matters here is that it never reads as more certain than it
/// is, and never lands below what was actually spent by a wide margin.
final class TokenEstimateTests: XCTestCase {
    func testNothingCostsNothing() {
        XCTAssertEqual(TokenEstimate.tokens(in: ""), 0)
        XCTAssertEqual(TokenEstimate.tokens(in: "   \n "), 0)
    }

    /// Latin text goes at roughly four characters to a token.
    func testLatinTextGoesFourCharactersToATheToken() {
        let text = String(repeating: "a", count: 400)

        XCTAssertEqual(TokenEstimate.tokens(in: text), 100)
    }

    /// Cyrillic is split far more finely by the common tokenizers, so the
    /// divisor is smaller. Using the Latin one here would understate a Russian
    /// round by a third and the counter would drift low all month.
    func testCyrillicTextGoesFewerCharactersToTheToken() {
        let text = String(repeating: "я", count: 400)

        XCTAssertEqual(TokenEstimate.tokens(in: text), 160)
    }

    /// A Russian sentence with a few Latin words in it is still Russian.
    func testMixedTextFollowsTheLetterThatDominates() {
        let cyrillic = String(repeating: "я", count: 300)
        let latin = String(repeating: "a", count: 100)

        XCTAssertEqual(TokenEstimate.tokens(in: cyrillic + latin), 160)
    }

    /// Rounding down would let a short round cost nothing at all, and a month
    /// of short rounds would show zero.
    func testAnythingAtAllCostsAtLeastOneToken() {
        XCTAssertEqual(TokenEstimate.tokens(in: "hi"), 1)
    }
}
