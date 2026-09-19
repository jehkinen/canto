import Foundation

/// Deterministic clean-up of recognized speech: the "Basic" mode, and the safety net under AI modes.
/// The words each rule needs (phantom sentences, punctuation commands…) come from the language files
/// in `Languages`, so the rules here are the same for every language.
public enum TextCleanup {
    // MARK: Whisper artifacts

    /// Whole sentences Whisper produces on silence or noise (it learned them from video subtitles).
    static let phantomSentences = Set(LanguagePack.bundled.flatMap(\.phantomSentences))

    /// Subtitle credits ("Субтитры делал DimaTorzok", "Subtitles by …"): Whisper learned them from
    /// video subtitles and writes them on silence. They open a sentence and are followed by a name;
    /// everything from them to the end is noise. The same words inside a sentence are real speech.
    static let creditPatterns = LanguagePack.bundled.flatMap(\.creditPatterns)

    static let creditExpression = try! NSRegularExpression(
        pattern: creditPatterns.joined(separator: "|"),
        options: [.caseInsensitive]
    )

    /// Sounds Whisper puts in parentheses: "(музыка)", "(applause)".
    static let soundWords = LanguagePack.bundled.flatMap(\.soundWords).joined(separator: "|")

    /// Sound events Whisper writes instead of words: "*Police*", "[Music]", "(applause)", "♪".
    /// Only words: "2*3*4" and "[1, 2, 3]" are what the user said.
    static let soundTag = try! NSRegularExpression(
        pattern: "\\s*(?:\\*(?=[^*\\n]*\\p{L})[^*\\n\\d]{1,40}\\*|\\[(?=[^\\]\\n]*\\p{L})[^\\]\\n\\d]{1,40}\\]"
            + "|\\(\\s*(?:\(soundWords))[^)\\n\\d]{0,30}\\)|♪[^♪\\n]{0,60}♪)",
        options: [.caseInsensitive]
    )

    /// Drops sound tags, loops, subtitle credits and phantom sentences at the end of a transcript.
    public static func removeWhisperArtifacts(_ text: String) -> String {
        var result = soundTag.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        // Loops before the other filters, as the study of Whisper hallucinations advises
        // (arXiv 2501.11378); after the tags, so "Спасибо. [Music] Спасибо." reads as copies.
        result = removeLoops(result)
        if let start = creditStart(in: result) {
            result = String(result[..<start])
        }
        while let range = lastSentenceRange(in: result), phantomSentences.contains(normalized(String(result[range]))) {
            result = String(result[..<range.lowerBound])
        }
        // A recording that starts mid-word reads to Whisper like a line of dialogue: "— и тогда…".
        // A minus before a number stays: "–5 градусов".
        result = result.replacingOccurrences(of: "^\\s*(?:[—–](?!\\s*\\d)|-(?=\\s)(?!\\s*\\d)|\\.{3}|…)\\s*", with: "",
                                             options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where a subtitle credit begins: a sentence that opens with a credit line followed by a
    /// name or nothing ("Субтитры делал DimaTorzok"), or the sentence that mentions amara.org.
    static func creditStart(in text: String) -> String.Index? {
        let starts = sentenceStarts(in: text)
        var found = text.range(of: "amara.org", options: .caseInsensitive).flatMap { amara in
            starts.last { $0 <= amara.lowerBound }
        }
        for start in starts where found.map({ start < $0 }) ?? true {
            guard let first = text[start...].firstIndex(where: { !$0.isWhitespace && !"—–-".contains($0) }),
                  let match = creditExpression.firstMatch(in: text, options: [.anchored], range: NSRange(first..., in: text)),
                  let matched = Range(match.range, in: text) else { continue }
            let tail = text[matched.upperBound...].drop { $0.isWhitespace || ":—–-".contains($0) }
            let name = tail.prefix { !$0.isWhitespace }
            // "Субтитры создали автоматически, …" goes on in ordinary words: that is speech.
            if name.isEmpty || name.first?.isUppercase == true || name.contains(where: { $0.isASCII && $0.isLetter }) {
                found = start
                break
            }
        }
        return found
    }

    /// Sentence beginnings: the start and every position after ". ", "! ", "? ", "… " or a line break.
    /// A dot inside a word ("Node.js", "А.Семкин") does not end a sentence.
    static func sentenceStarts(in text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if text[index] == "\n" || ([".", "!", "?", "…"].contains(text[index]) && (next == text.endIndex || text[next].isWhitespace)) {
                starts.append(next)
            }
            index = next
        }
        return starts
    }

    // MARK: Loops

    /// A word with the spaces and punctuation after it, up to the next word.
    struct LoopWord {
        var text: String
        /// What copies are compared by: lowercased, without punctuation.
        let key: String

        /// The word without what follows it: "Спасибо" of "Спасибо. ".
        var core: Substring {
            text[..<(text.lastIndex { $0.isLetter || $0.isNumber }.map(text.index(after:)) ?? text.endIndex)]
        }

        var tail: Substring { text[core.endIndex...] }

        var endsSentence: Bool { tail.contains { ".!?…\n".contains($0) } }
    }

    /// Phrases up to this many words are compared wherever they start: a loop that begins mid-sentence
    /// is short ("I'm going to the I'm going to the …"). Longer stretches are compared only as whole
    /// sentences, which is how Whisper repeats them.
    static let longestLoopPhrase = 8

    /// Whisper's loops: the same word, phrase or sentence three or more times in a row becomes one
    /// copy, "Спасибо. Спасибо. Спасибо." → "Спасибо.". Two copies stay: people say "да да" and repeat
    /// a sentence. Numbers and words repeated on purpose ("да да да") stay too. The first copy is kept
    /// as written, with the punctuation of the last one; the rest of the text is not touched.
    static func removeLoops(_ text: String) -> String {
        let (lead, found) = loopWords(in: text)
        var words = found
        var changed = true
        // Another pass after a change: the shorter text can close a loop that began earlier,
        // "я думаю я думаю я я я думаю" is "я думаю" three times once "я я я" is gone.
        while changed {
            changed = false
            var index = 0
            while index < words.count {
                guard let (length, copies) = loop(in: words, at: index) else {
                    index += 1
                    continue
                }
                let last = index + copies * length - 1
                words[index + length - 1].text = String(words[index + length - 1].core) + words[last].tail
                words.removeSubrange(index + length...last)
                changed = true
            }
        }
        return lead + words.map(\.text).joined()
    }

    /// The words of a text, and what comes before the first one.
    static func loopWords(in text: String) -> (lead: String, words: [LoopWord]) {
        var lead = ""
        var words: [LoopWord] = []
        var start = text.startIndex
        while start < text.endIndex {
            let tokenEnd = text[start...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let end = text[tokenEnd...].firstIndex { !$0.isWhitespace } ?? text.endIndex
            let key = normalized(String(text[start..<tokenEnd]))
            if !key.isEmpty {
                words.append(LoopWord(text: String(text[start..<end]), key: key))
            } else if words.isEmpty {
                lead += text[start..<end]
            } else {
                // A dash or dots on their own belong to the word before them.
                words[words.count - 1].text += text[start..<end]
            }
            start = end
        }
        return (lead, words)
    }

    /// The loop that starts at a word: the length of its unit and how many copies follow each other.
    /// The shortest unit wins, so "и я и я и я" is "и я" three times. A unit longer than a phrase is
    /// the whole sentence that starts here.
    static func loop(in words: [LoopWord], at index: Int) -> (length: Int, copies: Int)? {
        let longest = (words.count - index) / 3
        var lengths = Array(stride(from: 1, through: min(longestLoopPhrase, longest), by: 1))
        if index == 0 || words[index - 1].endsSentence,
           let end = words[index..<index + longest].firstIndex(where: \.endsSentence), end - index >= longestLoopPhrase {
            lengths.append(end - index + 1)
        }
        for length in lengths {
            // The first word must come back twice; that rules out almost every length cheaply.
            guard words[index + length].key == words[index].key, words[index + 2 * length].key == words[index].key,
                  isLoop(words[index..<index + length].map(\.key)) else { continue }
            var copies = 1
            while index + (copies + 1) * length <= words.count,
                  (0..<length).allSatisfy({ words[index + $0].key == words[index + copies * length + $0].key }) {
                copies += 1
            }
            if copies >= 3 { return (length, copies) }
        }
        return nil
    }

    /// Whether a unit said three times in a row is a loop rather than something people say.
    static func isLoop(_ unit: [String]) -> Bool {
        // Numbers repeat for real: "пять пять пять", a phone number "12 12 12".
        if unit.joined(separator: " ").split(separator: " ").allSatisfy({ isNumber(String($0)) }) { return false }
        if unit.count == 1 { return !intentionalRepeats.contains(unit[0]) }
        // A unit that is itself a repeat was already judged as its shorter unit: "да да" is "да".
        return !(1..<unit.count).contains { period in
            unit.count % period == 0 && unit.indices.allSatisfy { unit[$0] == unit[$0 % period] }
        }
    }

    // MARK: Basic mode

    /// Collapsed repetitions, tidy spacing and a capital first letter.
    public static func basic(_ text: String) -> String {
        capitalizeFirstLetter(normalizeSpacing(collapseRepeats(text)))
    }

    /// Words that people repeat on purpose ("да да", "very very", "давай, давай, давай") and should stay repeated.
    static let intentionalRepeats = Set(LanguagePack.bundled.flatMap(\.intentionalRepeats))

    /// Removes immediate repetitions of one to three words, a typical speech-to-text stutter:
    /// "мы мы пойдём" → "мы пойдём", "под каждую под каждую систему" → "под каждую систему".
    public static func collapseRepeats(_ text: String) -> String {
        var words = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var index = 0
        while index < words.count {
            var collapsed = false
            for length in stride(from: 3, through: 1, by: -1) where index + 2 * length <= words.count {
                let first = words[index..<index + length].map(normalized)
                let second = words[index + length..<index + 2 * length].map(normalized)
                guard first == second, first.allSatisfy({ !$0.isEmpty }) else { continue }
                if length == 1, intentionalRepeats.contains(first[0]) { continue }
                // Numbers repeat for real: "пять пять пять", "код один один два".
                if first.allSatisfy(isNumber) { continue }
                // Keep the second copy: it carries the punctuation that follows the phrase.
                words.removeSubrange(index..<index + length)
                collapsed = true
                break
            }
            if !collapsed { index += 1 }
        }
        return words.joined(separator: " ")
    }

    /// Single spaces, no space before punctuation, one space after it before a word.
    public static func normalizeSpacing(_ text: String) -> String {
        var result = text
        let rules: [(String, String)] = [
            ("[ \\t]+", " "),
            (" *\\n *", "\n"),
            (" +([,.;:!?…)»])", "$1"),
            ("([(«]) +", "$1"),
            ("([,;:!?])(?=[\\p{L}])", "$1 "),
            ("(?<=[\\p{L}])\\.(?=[\\p{Lu}])", ". "),
        ]
        for (pattern, template) in rules {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Number words of languages `SpokenNumbers` does not read yet.
    static let numberWords = Set(LanguagePack.bundled.flatMap(\.numberWords))

    static func isNumber(_ word: String) -> Bool {
        word.allSatisfy(\.isNumber) || SpokenNumbers.units[word] != nil || SpokenNumbers.multipliers[word] != nil
            || numberWords.contains(word)
    }

    public static func capitalizeFirstLetter(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }

    // MARK: Spoken punctuation

    struct SpokenCommand {
        var words: String
        var symbol: String
        /// Words before the command that make it an ordinary noun: "стартовая точка", "the trial period".
        var notAfter: Set<String> = []
        var notAfterEndings: [String] = []
        /// Between two numbers the word is a decimal point, not punctuation: "один точка пять".
        var decimalPoint = false
    }

    /// Spoken commands and what they insert, from every language file. A command is skipped in set
    /// phrases like "точка зрения" (its `notBefore` words).
    static let spokenCommands: [SpokenCommand] = LanguagePack.bundled.flatMap { pack in
        pack.punctuation.map { command in
            let setPhrases = command.notBefore.isEmpty ? "" : "(?!\\s+(?:\(command.notBefore.joined(separator: "|"))))"
            return SpokenCommand(words: command.words + setPhrases, symbol: command.symbol, notAfter: pack.expand(command.notAfter),
                                 notAfterEndings: command.notAfterEndings, decimalPoint: command.decimalPoint)
        }
    }

    static let spokenCommandExpressions: [(NSRegularExpression, SpokenCommand)] = spokenCommands.map { command in
        let phrase = command.words.replacingOccurrences(of: " ", with: "\\s+")
        // The command must follow a word; punctuation Whisper already put around it is absorbed,
        // so "app, comma, running" becomes "app, running" rather than "app,,, running".
        let pattern = "(?<=\\S)[ \\t]*[,.;:]?[ \\t]+\\b\(phrase)\\b[,.;:!?]*"
        return (try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), command)
    }

    public static func applySpokenPunctuation(_ text: String) -> String {
        var result = text
        for (expression, command) in spokenCommandExpressions {
            let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let previous = result[..<range.lowerBound].split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last
                    .map { $0.lowercased() } ?? ""
                if command.notAfter.contains(previous) || command.notAfterEndings.contains(where: previous.hasSuffix) {
                    continue
                }
                let spoken = result[range].trimmingCharacters(in: .whitespaces)
                if command.decimalPoint, spoken.allSatisfy(\.isLetter),
                   SpokenNumbers.isDecimalPoint(spoken, before: result[..<range.lowerBound], after: result[range.upperBound...]) {
                    continue
                }
                var rest = String(result[range.upperBound...])
                // A new sentence or line starts with a capital letter.
                if [".", "?", "!", "\n", "\n\n"].contains(command.symbol),
                   let letter = rest.firstIndex(where: { !$0.isWhitespace }), rest[letter].isLowercase {
                    rest.replaceSubrange(letter...letter, with: rest[letter].uppercased())
                }
                result = String(result[..<range.lowerBound]) + command.symbol + rest
            }
        }
        return result
    }

    // MARK: Helpers

    /// Lowercased letters and digits separated by single spaces.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// The range of the last sentence, from after the previous terminator to the end.
    static func lastSentenceRange(in text: String) -> Range<String.Index>? {
        let terminators: Set<Character> = [".", "!", "?", "…", "\n"]
        var end = text.endIndex
        while end > text.startIndex, let previous = Optional(text.index(before: end)),
              terminators.contains(text[previous]) || text[previous].isWhitespace {
            end = previous
        }
        guard end > text.startIndex else { return nil }
        let start = text[..<end].lastIndex(where: { terminators.contains($0) }).map { text.index(after: $0) } ?? text.startIndex
        return start..<text.endIndex
    }
}
