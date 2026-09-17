import Foundation

/// A phrase that ends a dictation and presses Return, for example to send a chat message.
public enum EnterPhrase {
    /// Removes `phrase` from the end of `text`. Case, trailing punctuation and spacing are ignored.
    public static func strip(_ text: String, phrase: String?) -> (text: String, pressEnter: Bool) {
        let trimmedPhrase = (phrase ?? "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmedPhrase.isEmpty else { return (text, false) }

        let body = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?…")))
        guard let range = body.range(of: trimmedPhrase, options: [.caseInsensitive, .backwards, .anchored]) else {
            return (text, false)
        }
        // Whole words only: "отправь" must not fire inside "переотправь".
        if range.lowerBound > body.startIndex, body[body.index(before: range.lowerBound)].isLetter {
            return (text, false)
        }
        let rest = body[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:—-")))
        return (rest, true)
    }
}
