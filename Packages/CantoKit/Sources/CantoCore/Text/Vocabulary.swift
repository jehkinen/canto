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

    public static func apply(_ text: String, terms raw: [String]) -> String {
        var result = text
        // Longer terms first, so "ChatGPT" wins over "GPT".
        for term in terms(raw).sorted(by: { $0.count > $1.count }) {
            guard let expression = expression(for: term) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range,
                                                         withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
        return result
    }

    /// Whisper answers near-silence with the prompt it was given: the whole list, part of it, or
    /// a couple of terms. Text that is nothing but dictionary terms is such an echo, and a phrase
    /// with a single term ("ChatGPT") is left alone because it is something people do dictate.
    public static func isEchoOfPrompt(_ text: String, terms raw: [String]) -> Bool {
        let list = terms(raw)
        guard !list.isEmpty else { return false }
        var rest = text
        var matches = 0
        for term in list.sorted(by: { $0.count > $1.count }) {
            guard let expression = expression(for: term) else { continue }
            let range = NSRange(rest.startIndex..., in: rest)
            matches += expression.numberOfMatches(in: rest, range: range)
            rest = expression.stringByReplacingMatches(in: rest, range: range, withTemplate: "")
        }
        let leftovers = rest.filter { $0.isLetter || $0.isNumber }
        return matches >= 2 && leftovers.isEmpty
    }

    /// Matches the term's parts with optional spaces, hyphens or dots between them, as a whole word.
    static func expression(for term: String) -> NSRegularExpression? {
        let parts = self.parts(of: term)
        guard !parts.isEmpty else { return nil }
        // Between parts: nothing, a space, a dot, a hyphen or an underscore, optionally with spaces ("Node. js").
        let body = parts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "(?:\\s?[\\-_.]?\\s?)")
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
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
