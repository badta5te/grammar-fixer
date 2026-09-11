import XCTest
@testable import GrammarFixerCore

/// What the panel highlights. The comparison is by whole visual words, so a
/// comma the model added shows up on the word it hangs on rather than as a
/// lone mark floating between two untouched words.
final class WordDiffTests: XCTestCase {
    private func diff(_ before: String, _ after: String) -> WordDiff.Result {
        WordDiff.between(before, and: after)
    }

    /// The changed words, in order, as the panel would tint them.
    private func changed(_ before: String, _ after: String) -> [String] {
        diff(before, after).pieces.filter(\.isChanged).map(\.text)
    }

    func testTextThatWasNotTouchedIsNotHighlighted() {
        let result = diff("Привет, как дела?", "Привет, как дела?")

        XCTAssertEqual(result.changes, 0)
        XCTAssertEqual(result.pieces.filter(\.isChanged), [])
        XCTAssertEqual(result.text, "Привет, как дела?")
    }

    func testAReplacedWordIsHighlighted() {
        XCTAssertEqual(changed("карова даёт молоко", "корова даёт молоко"), ["корова"])
        XCTAssertEqual(diff("карова даёт молоко", "корова даёт молоко").changes, 1)
    }

    /// The commonest correction of all. A comma is part of the word it follows,
    /// so the word carries the highlight and the number counts one place.
    func testACommaTheModelAddedShowsOnTheWordItHangsOn() {
        let result = diff("Привет как дела", "Привет, как дела")

        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["Привет,"])
        XCTAssertEqual(result.changes, 1)
    }

    func testAnInsertedWordIsHighlighted() {
        XCTAssertEqual(changed("иду магазин", "иду в магазин"), ["в"])
    }

    /// A word the model removed is not in the text any more, so the gap it
    /// stood in carries the mark.
    func testAWordTheModelRemovedLeavesItsMarkOnTheGap() {
        let result = diff("я иду иду домой", "я иду домой")

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.text, "я иду домой")
        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), [" "])
    }

    /// A word taken off the very front or the very end has no gap to leave a
    /// mark in: the answer arrives trimmed, so there is no space there at all.
    /// The word beside the hole carries it instead — otherwise the footer would
    /// count a change with nothing on screen behind the number, which is the
    /// one thing the mark exists to prevent.
    func testAWordRemovedAtEitherEndOfTheTextStillLeavesAMark() {
        let fromTheFront = diff("Ну привет, как дела?", "привет, как дела?")
        XCTAssertEqual(fromTheFront.changes, 1)
        XCTAssertEqual(fromTheFront.pieces.filter(\.isChanged).map(\.text), ["привет,"])

        let fromTheEnd = diff("спасибо большое большое", "спасибо большое")
        XCTAssertEqual(fromTheEnd.changes, 1)
        XCTAssertEqual(fromTheEnd.pieces.filter(\.isChanged).map(\.text), ["большое"])
    }

    /// Where the model swapped a phrase it both took words out and put words
    /// in, all in one place. The new words carry the highlight on their own:
    /// marking the gap beside them as well would smear the tint onto the
    /// untouched word before.
    func testAPhraseTheModelRewroteIsOnePlaceWithOnlyTheNewWordsTinted() {
        let result = diff("я иду в магазин", "я пошёл магазин")

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["пошёл"])
    }

    /// A whole phrase the model inserted is one place, not one per word, and
    /// one highlight rather than a row of them.
    func testSeveralInsertedWordsAreOnePlaceAndOneHighlight() {
        let result = diff("иду магазин", "иду в большой магазин")

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["в большой"])
    }

    // MARK: - Russian

    /// The dots on ё are a correction, and the one thing a diacritic-blind
    /// comparison would quietly swallow.
    func testPuttingTheDotsOnYoIsAChange() {
        XCTAssertEqual(changed("все пришли", "всё пришли"), ["всё"])
    }

    func testAWordThatAlreadyHadItsYoIsLeftAlone() {
        XCTAssertEqual(diff("всё пришли", "всё пришли").changes, 0)
    }

    /// Some apps hand the selection over with ё written as two code points.
    /// Comparing strings is canonical, so that is the same word and no phantom
    /// change appears — while a ё the model really did add is still a change,
    /// which is what stops anybody from "fixing" the first case by normalizing
    /// the dots away.
    func testYoWrittenAsTwoCodePointsIsTheSameWord() {
        let composed = "всё пришли"

        XCTAssertEqual(diff(composed.decomposedStringWithCanonicalMapping, composed).changes, 0)
        XCTAssertEqual(
            changed("все пришли".decomposedStringWithCanonicalMapping, composed),
            ["всё"]
        )
    }

    /// A capital letter is a correction too, and case-insensitive comparison
    /// would lose exactly the correction people ask for most after commas.
    func testACapitalLetterIsAChange() {
        XCTAssertEqual(changed("привет, как дела", "Привет, как дела"), ["Привет,"])
    }

    func testAHyphenatedWordThatDidNotChangeIsNotHighlighted() {
        XCTAssertEqual(diff("он говорит по-русски", "он говорит по-русски").changes, 0)
    }

    /// Two words joined by a hyphen are one word afterwards, which is one place
    /// touched rather than two.
    func testJoiningTwoWordsWithAHyphenIsOneChange() {
        let result = diff("что то не так", "что-то не так")

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["что-то"])
    }

    // MARK: - What the panel shows

    /// The one invariant the rendering rests on: the pieces put back together
    /// are the answer itself, down to the newlines and the double spaces.
    func testThePiecesPutBackTogetherAreTheAnswer() {
        let after = "Привет!\n\nКак  дела? 👋 https://example.com/a?b=1"
        let result = diff("привет\n\nкак  дела 👋 https://example.com/a?b=1", after)

        XCTAssertEqual(result.text, after)
    }

    func testALinkIsOneWordAndIsLeftAlone() {
        let result = diff(
            "смотри https://example.com/путь?q=1 тут",
            "Смотри https://example.com/путь?q=1 тут"
        )

        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["Смотри"])
    }

    /// Two words next to each other, both touched, are one highlight rather
    /// than two with a gap down the middle of it — and one place, not two.
    func testNeighbouringChangesAreOneHighlight() {
        let result = diff("мама мыла раму", "Мама помыла раму")

        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["Мама помыла"])
        XCTAssertEqual(result.changes, 1)
    }

    /// Two touched words with an untouched one between them are two places, and
    /// the word between them keeps its plain background.
    func testWordsTouchedInTwoPlacesAreCountedTwice() {
        let result = diff("карова даёт малако", "корова даёт молоко")

        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["корова", "молоко"])
        XCTAssertEqual(result.changes, 2)
    }

    func testACapitalAndAQuestionMarkAreTwoPlaces() {
        XCTAssertEqual(diff("привет как дела", "Привет, как дела?").changes, 2)
    }

    /// The identical head comes off before the comparison, so every mark lands
    /// on an index that has been shifted. A full stop added at the very end is
    /// the case where a shift that is one out would tint the wrong word.
    func testAFullStopAddedAtTheEndHighlightsTheLastWord() {
        XCTAssertEqual(changed("она пришла домой", "она пришла домой!"), ["домой!"])
    }

    /// A selection usually arrives with an indent or a trailing newline. It is
    /// not a word, so it carries no highlight, and it has to come back out
    /// untouched: the panel draws the runs while ⏎ pastes the answer itself, so
    /// anything the runs lose is a panel showing something else.
    func testWhitespaceAroundTheSelectionIsKeptAndLeftPlain() {
        let after = "  Привет, мир\n"
        let result = diff("  привет мир\n", after)

        XCTAssertEqual(result.text, after)
        XCTAssertEqual(result.pieces.filter(\.isChanged).map(\.text), ["Привет,"])
        XCTAssertEqual(result.changes, 1)
    }

    // MARK: - Edges

    func testAnEmptyAnswerHasNothingToShow() {
        let result = diff("текст", "")

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.pieces.filter(\.isChanged), [])
    }

    func testEverythingIsNewWhenThereWasNothingBefore() {
        let result = diff("", "Привет, как дела?")

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.text, "Привет, как дела?")
        XCTAssertTrue(result.pieces.allSatisfy(\.isChanged))
    }

    func testWhitespaceOnlyTextIsNotAChangeAndComesBackWhole() {
        let result = diff("  \n ", "  \n ")

        XCTAssertEqual(result.changes, 0)
        XCTAssertEqual(result.text, "  \n ")
    }

    /// Comparing word by word costs the product of the two lengths. Past a
    /// point the answer is shown as one changed stretch instead, which is worse
    /// highlighting and still an honest count — a panel that stalls on a long
    /// selection would be the worse trade.
    func testAnOversizedComparisonFallsBackToOneStretch() {
        let before = (1 ... 60).map { "слово\($0)" }.joined(separator: " ")
        let after = (1 ... 60).map { "СЛОВО\($0)" }.joined(separator: " ")

        let result = WordDiff.between(before, and: after, limit: 100)

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.text, after)
        XCTAssertTrue(result.pieces.allSatisfy(\.isChanged))
    }

    /// Past the limit the changed middle is shown as one stretch, but the head
    /// and tail that came off before the comparison are untouched text and have
    /// to stay plain. The coarse fallback is not a licence to tint the whole
    /// answer.
    func testTheOversizedFallbackLeavesTheTrimmedHeadAndTailPlain() {
        let head = "Первое предложение осталось как было."
        let tail = "И последнее тоже осталось на месте."
        let middle = (1 ... 60).map { "СЛОВО\($0)" }.joined(separator: " ")
        let before = "\(head) \((1 ... 60).map { "слово\($0)" }.joined(separator: " ")) \(tail)"
        let after = "\(head) \(middle) \(tail)"

        let result = WordDiff.between(before, and: after, limit: 100)

        XCTAssertEqual(result.changes, 1)
        XCTAssertEqual(result.text, after)
        XCTAssertEqual(result.pieces.map(\.isChanged), [false, true, false])
        XCTAssertEqual(result.pieces[1].text, middle)
    }

    /// The fallback must not fire on anything a person would actually select.
    func testAParagraphIsWellWithinTheLimit() {
        let before = String(repeating: "слово раз два три ", count: 40)
        let after = before.replacingOccurrences(of: "раз", with: "разъ")

        XCTAssertEqual(WordDiff.between(before, and: after).changes, 40)
    }
}

/// The footer number. "1 changes" would read as a bug in everything else the
/// footer says.
final class ChangeCountLineTests: XCTestCase {
    func testTheFooterCountsInWords() {
        XCTAssertEqual(TextMetrics.describeChanges(0), "no changes")
        XCTAssertEqual(TextMetrics.describeChanges(1), "1 change")
        XCTAssertEqual(TextMetrics.describeChanges(4), "4 changes")
    }
}
