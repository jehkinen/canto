import Foundation

/// Deterministic clean-up of recognized speech: the "Basic" mode, and the safety net under AI modes.
public enum TextCleanup {
    // MARK: Whisper artifacts

    /// Whole sentences Whisper produces on silence or noise (it learned them from video subtitles).
    static let phantomSentences: Set<String> = [
        "спасибо за просмотр", "спасибо за внимание", "продолжение следует", "подписывайтесь на канал",
        "ставьте лайки и подписывайтесь на канал", "до новых встреч",
        "thanks for watching", "thank you for watching", "please subscribe", "subscribe to my channel",
    ]

    /// Subtitle credits; everything from them to the end is noise.
    static let creditMarkers = [
        "субтитры сделал", "субтитры создавал", "субтитры подготовил", "редактор субтитров",
        "subtitles by", "transcribed by", "captions by",
    ]

    /// Drops subtitle credits and phantom sentences at the end of a transcript.
    public static func removeWhisperArtifacts(_ text: String) -> String {
        var result = text
        for marker in creditMarkers {
            if let range = result.range(of: marker, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
            }
        }
        while let range = lastSentenceRange(in: result), phantomSentences.contains(normalized(String(result[range]))) {
            result = String(result[..<range.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Basic mode

    /// Collapsed repetitions, tidy spacing and a capital first letter.
    public static func basic(_ text: String) -> String {
        capitalizeFirstLetter(normalizeSpacing(collapseRepeats(text)))
    }

    /// Words that people repeat on purpose ("да да", "very very") and should stay doubled.
    static let intentionalRepeats: Set<String> = [
        "да", "нет", "очень", "ну", "ха", "хи", "бла", "так", "very", "yes", "no", "ha", "so", "bye", "пока",
    ]

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

    public static func capitalizeFirstLetter(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }

    // MARK: Spoken punctuation

    /// Spoken commands and what they insert. "Точка" is skipped in set phrases like "точка зрения".
    static let spokenPunctuation: [(words: String, symbol: String)] = [
        ("вопросительный знак", "?"), ("восклицательный знак", "!"), ("новый абзац", "\n\n"), ("новая строка", "\n"),
        ("запятая", ","), ("двоеточие", ":"), ("точка(?!\\s+(?:зрения|отсч[её]та|опоры|кипения|доступа|входа|роста|невозврата))", "."),
        ("question mark", "?"), ("exclamation mark", "!"), ("exclamation point", "!"), ("new paragraph", "\n\n"),
        ("new line", "\n"), ("comma", ","), ("colon", ":"), ("full stop", "."), ("period", "."),
    ]

    nonisolated(unsafe) static let spokenPunctuationExpressions: [(NSRegularExpression, String)] = spokenPunctuation.map { words, symbol in
        let phrase = words.replacingOccurrences(of: " ", with: "\\s+")
        // The command must follow a word; punctuation Whisper already put around it is absorbed,
        // so "app, comma, running" becomes "app, running" rather than "app,,, running".
        let pattern = "(?<=\\S)[ \\t]*[,.;:]?[ \\t]+\\b\(phrase)\\b[,.;:!?]*"
        return (try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), symbol)
    }

    public static func applySpokenPunctuation(_ text: String) -> String {
        var result = text
        for (expression, symbol) in spokenPunctuationExpressions {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range,
                                                         withTemplate: NSRegularExpression.escapedTemplate(for: symbol))
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
