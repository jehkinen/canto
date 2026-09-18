import Foundation

/// User terms such as "OpenAI" or "ChatGPT" that must keep their spelling.
/// They go to the recognizer as a prompt (biasing it toward that spelling at no extra cost) and
/// afterwards restore the exact form: "openai", "Open AI", "chat-gpt" become "OpenAI", "ChatGPT".
public enum Vocabulary {
    /// Trimmed, non-empty terms without case-insensitive duplicates, in the user's order.
    public static func terms(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { term in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    /// The recognition prompt, or `nil` when there are no terms. For Russian the list is framed by a
    /// Russian word: a bare list of Latin terms pulls small models into writing Russian in Latin letters.
    /// With auto-detection there is no framing, so the prompt does not tip the language guess.
    public static func prompt(for raw: [String], language: String? = nil) -> String? {
        let list = terms(raw)
        guard !list.isEmpty else { return nil }
        let joined = list.joined(separator: ", ") + "."
        return language == "ru" ? "Термины: " + joined : joined
    }

    /// Restores the exact spelling of every term, in one pass: a shorter term never rewrites a
    /// longer one's replacement ("JS" inside "Node.js").
    public static func apply(_ text: String, terms raw: [String]) -> String {
        guard let (expression, ordered) = combinedExpression(for: raw) else { return text }
        var result = text
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let term = matchedTerm(match, terms: ordered), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: keepingCapital(of: result[range], in: term))
        }
        return result
    }

    /// A lowercase term keeps the capital the sentence gave it: "Запушить в main" stays capitalized.
    private static func keepingCapital(of matched: Substring, in term: String) -> String {
        guard let first = matched.first, first.isUppercase, let termFirst = term.first, termFirst.isLowercase else { return term }
        return termFirst.uppercased() + term.dropFirst()
    }

    /// Whisper answers near-silence with the prompt it was given: the terms in the prompt's order,
    /// each once, sometimes after the Russian framing word. A phrase with a single term
    /// ("ChatGPT"), a repeated one ("Go, go, go!") or terms in another order is real speech.
    public static func isEchoOfPrompt(_ text: String, terms raw: [String]) -> Bool {
        let list = terms(raw)
        guard let (expression, ordered) = combinedExpression(for: raw) else { return false }
        let body = text.replacingOccurrences(of: "^\\s*термины\\s*:?", with: "", options: [.regularExpression, .caseInsensitive])
        let matches = expression.matches(in: body, range: NSRange(body.startIndex..., in: body))
        let positions = matches.compactMap { matchedTerm($0, terms: ordered) }.compactMap { term in
            list.firstIndex(of: term)
        }
        guard positions.count >= 2, zip(positions, positions.dropFirst()).allSatisfy({ $0 < $1 }) else { return false }
        let rest = expression.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "")
        return !rest.contains { $0.isLetter || $0.isNumber }
    }

    /// One expression for all terms, longest first so "ChatGPT" wins over "GPT"; group `i + 1`
    /// matches `ordered[i]`.
    static func combinedExpression(for raw: [String]) -> (NSRegularExpression, [String])? {
        let ordered = terms(raw).sorted { $0.count > $1.count }
        let bodies = ordered.compactMap(body(for:))
        guard !ordered.isEmpty, bodies.count == ordered.count else { return nil }
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + bodies.map { "(\($0))" }.joined(separator: "|") + ")(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return (expression, ordered)
    }

    private static func matchedTerm(_ match: NSTextCheckingResult, terms: [String]) -> String? {
        (1..<match.numberOfRanges).first { match.range(at: $0).location != NSNotFound }.map { terms[$0 - 1] }
    }

    /// Matches the term's parts with optional spaces, hyphens or dots between them. Symbols before
    /// or after the letters ("C++", "C#", ".NET") are required as written, so "plan c" stays.
    static func expression(for term: String) -> NSRegularExpression? {
        body(for: term).flatMap { try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\($0))(?![\\p{L}\\p{N}])",
                                                            options: [.caseInsensitive]) }
    }

    static func body(for term: String) -> String? {
        let parts = self.parts(of: term)
        guard !parts.isEmpty else { return nil }
        let isWordCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        let leading = String(term.prefix { !isWordCharacter($0) })
        let trailing = String(term.reversed().prefix { !isWordCharacter($0) }.reversed())
        // Between parts: nothing, a space, a hyphen or an underscore, or a dot ("Node. js"). A dot
        // and a space before a capital letter ends a sentence: "open. AI" is not "OpenAI".
        let separator = "(?:\\s?[\\-_]\\s?|\\s|\\.(?:\\s(?=(?-i:\\p{Ll})))?)?"
        let core = parts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: separator)
        return NSRegularExpression.escapedPattern(for: leading) + core + NSRegularExpression.escapedPattern(for: trailing)
    }

    /// "ChatGPT" → ["Chat", "GPT"], "OpenAI" → ["Open", "AI"], "gpt-4o" → ["gpt", "4o"].
    static func parts(of term: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for character in term {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { parts.append(current) }
                current = ""
                previous = nil
                continue
            }
            if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                parts.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
