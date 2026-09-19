import Foundation

/// A long recording is inserted phrase by phrase, and each phrase arrives trimmed: without a
/// separator "…will be." and "And then…" would be glued into "…will be.And then…".
public enum PhraseJoiner {
    /// What goes before `next` when it is inserted right after `previous`.
    public static func separator(after previous: String, before next: String) -> String {
        guard let last = previous.last, let first = next.first else { return "" }
        if last.isWhitespace || first.isWhitespace { return "" }
        if noSpaceBefore.contains(first) || noSpaceAfter.contains(last) { return "" }
        if isWrittenWithoutSpaces(last) || isWrittenWithoutSpaces(first) { return "" }
        return " "
    }

    private static let noSpaceBefore: Set<Character> = [",", ".", ";", ":", "!", "?", "…", ")", "]", "}", "»", "%"]
    private static let noSpaceAfter: Set<Character> = ["(", "[", "{", "«"]

    /// Chinese, Japanese and Thai put no spaces between sentences.
    private static func isWrittenWithoutSpaces(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x0E00...0x0E7F, // Thai
             0x3000...0x30FF, // CJK punctuation, Hiragana, Katakana
             0x3400...0x4DBF, 0x4E00...0x9FFF, // CJK ideographs
             0xFF00...0xFFEF: // Full-width forms
            return true
        default:
            return false
        }
    }
}
