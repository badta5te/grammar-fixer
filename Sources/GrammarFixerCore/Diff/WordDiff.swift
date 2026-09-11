import Foundation

/// What the model changed, word by word.
///
/// The comparison is by whole visual words — punctuation and all — rather than
/// by characters. Fixing grammar mostly means adding a comma or a letter, and
/// a character diff marks the comma alone: a tinted mark floating between two
/// untouched words tells nobody anything, while "Привет," tinted whole reads at
/// a glance. It also means a hyphen, an apostrophe or the dots on ё need no
/// special case: they are part of the word that carries them.
///
/// Nothing here knows about the panel. The result is a list of runs covering
/// the answer exactly, and whoever draws it decides what "highlighted" looks
/// like.
public enum WordDiff {
    /// One run of the answer, and whether the model touched it.
    public struct Piece: Equatable, Sendable {
        public var text: String
        public var isChanged: Bool
    }

    public struct Result: Equatable, Sendable {
        /// The answer in order. Joining these gives the answer back exactly,
        /// whitespace and newlines included.
        public var pieces: [Piece]

        /// How many places the model touched. A stretch of neighbouring words
        /// counts once: "three changes" is meant to read as "three places",
        /// which is what somebody deciding whether to trust the answer wants.
        public var changes: Int

        public var text: String { pieces.map(\.text).joined() }
    }

    /// Comparing word by word costs the product of the two word counts. Past
    /// this the answer is shown as a single changed stretch instead: worse
    /// highlighting, an honest count, and no panel that sits there grinding
    /// through a selection somebody pasted a book into.
    static let defaultLimit = 1_000_000

    public static func between(_ before: String, and after: String) -> Result {
        between(before, and: after, limit: defaultLimit)
    }

    static func between(_ before: String, and after: String, limit: Int) -> Result {
        let old = Split(text: before)
        let new = Split(text: after)

        // An answer with no words in it is nothing the panel ever shows: an
        // empty answer is refused long before here. It is still passed back
        // whole and unmarked, because whoever draws the runs draws them instead
        // of the answer, and runs that lost a character would be a panel
        // showing something other than what ⏎ pastes.
        guard !new.words.isEmpty else {
            return Result(
                pieces: new.leading.isEmpty ? [] : [Piece(text: new.leading, isChanged: false)],
                changes: 0
            )
        }
        guard !old.words.isEmpty else {
            return new.assemble(changed: Array(repeating: true, count: new.words.count), deletions: [], changes: 1)
        }

        // Grammar corrections leave most of the text alone, so the identical
        // head and tail are taken off first. That is both what keeps the
        // comparison cheap and what keeps the highlighting local.
        var head = 0
        while head < old.words.count, head < new.words.count, old.words[head] == new.words[head] {
            head += 1
        }
        var tail = 0
        while tail < old.words.count - head, tail < new.words.count - head,
              old.words[old.words.count - 1 - tail] == new.words[new.words.count - 1 - tail] {
            tail += 1
        }

        let oldMiddle = Array(old.words[head ..< old.words.count - tail])
        let newMiddle = Array(new.words[head ..< new.words.count - tail])

        var changed = Array(repeating: false, count: new.words.count)
        var deletions: Set<Int> = []
        var changes = 0

        if oldMiddle.isEmpty, newMiddle.isEmpty {
            // The two are the same text.
        } else if oldMiddle.count * newMiddle.count > limit {
            for index in head ..< new.words.count - tail { changed[index] = true }
            changes = 1
        } else {
            // The script is read in stretches: everything between two words
            // that survived is one place the model touched, however many words
            // it swapped there. A rewritten phrase is one change, not four.
            var added: [Int] = []
            var removed: [Int] = []

            func closeTheStretch() {
                guard !added.isEmpty || !removed.isEmpty else { return }
                changes += 1
                for index in added { changed[head + index] = true }
                // A word that was taken out and nothing put in its place has
                // nothing on screen to tint, so the gap where it stood carries
                // the mark instead — otherwise the footer would count a change
                // with nothing behind the number. Where a word was replaced,
                // the replacement is already tinted and marking the gap beside
                // it would only smear the highlight.
                if added.isEmpty, let index = removed.first {
                    deletions.insert(head + index)
                }
                added = []
                removed = []
            }

            for step in align(oldMiddle, newMiddle) {
                switch step {
                case .kept: closeTheStretch()
                case .added(let index): added.append(index)
                case .removed(let index): removed.append(index)
                }
            }
            closeTheStretch()
        }

        return new.assemble(changed: changed, deletions: deletions, changes: changes)
    }

    // MARK: - Splitting

    /// The answer as words and the whitespace between them. Whitespace is kept
    /// aside rather than compared: a space that became two is not a correction
    /// anybody can see, and tinting it would be noise.
    private struct Split {
        /// Whatever came before the first word.
        var leading: String
        var words: [String]
        /// What follows each word, in step with `words`.
        var gaps: [String]

        init(text: String) {
            leading = ""
            words = []
            gaps = []

            var current = ""
            var isWord = false
            for character in text {
                let belongsToAWord = !character.isWhitespace
                if belongsToAWord == isWord {
                    current.append(character)
                    continue
                }
                store(current, isWord: isWord)
                current = String(character)
                isWord = belongsToAWord
            }
            store(current, isWord: isWord)
        }

        private mutating func store(_ run: String, isWord: Bool) {
            guard !run.isEmpty else { return }
            if isWord {
                words.append(run)
                gaps.append("")
            } else if words.isEmpty {
                leading = run
            } else {
                gaps[gaps.count - 1] = run
            }
        }

        /// The runs to draw. Neighbouring words that both changed become one
        /// run together with the space between them, so a corrected phrase is
        /// one highlight rather than a row of them.
        ///
        /// `deletions` holds positions in `words`: a word was taken out from
        /// just before the word at that index.
        func assemble(changed: [Bool], deletions: Set<Int>, changes: Int) -> Result {
            var changed = changed
            var markedGaps: Set<Int> = []

            for position in deletions {
                let gap = position == 0 ? leading : gaps[position - 1]
                if gap.isEmpty {
                    // A word taken out of the middle leaves the whitespace it
                    // stood in, and that is what carries the mark. A word taken
                    // off the very front or the very end leaves nothing at all:
                    // the answer arrives trimmed, so there is no leading or
                    // trailing space to tint. The surviving word beside the
                    // hole carries the mark instead — it is not the word that
                    // changed, but it is where the change happened, and a
                    // footer counting a change with nothing on screen behind it
                    // is the worse of the two lies.
                    changed[min(position, words.count - 1)] = true
                } else {
                    markedGaps.insert(position)
                }
            }

            var pieces: [Piece] = []

            func append(_ text: String, isChanged: Bool) {
                guard !text.isEmpty else { return }
                if let last = pieces.last, last.isChanged == isChanged {
                    pieces[pieces.count - 1].text += text
                } else {
                    pieces.append(Piece(text: text, isChanged: isChanged))
                }
            }

            append(leading, isChanged: markedGaps.contains(0))
            for index in words.indices {
                append(words[index], isChanged: changed[index])
                let gapIsChanged = markedGaps.contains(index + 1)
                    || (changed[index] && index + 1 < words.count && changed[index + 1])
                append(gaps[index], isChanged: gapIsChanged)
            }

            return Result(pieces: pieces, changes: changes)
        }
    }

    // MARK: - Comparing

    private enum Step {
        /// The word is in both, at this index in the answer.
        case kept
        /// Only in the answer, at this index.
        case added(Int)
        /// Only in the original. The index is where it would have been in the
        /// answer.
        case removed(Int)
    }

    /// A longest-common-subsequence alignment, read out in order.
    ///
    /// Plain dynamic programming rather than anything cleverer: the head and
    /// tail are already gone by the time this runs, so what is left is the
    /// handful of words the model actually rewrote.
    private static func align(_ old: [String], _ new: [String]) -> [Step] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = old[i] == new[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var script: [Step] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                script.append(.kept)
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                script.append(.removed(j))
                i += 1
            } else {
                script.append(.added(j))
                j += 1
            }
        }
        while i < old.count {
            script.append(.removed(j))
            i += 1
        }
        while j < new.count {
            script.append(.added(j))
            j += 1
        }
        return script
    }
}
