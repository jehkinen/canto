import Foundation

/// Writes whole numbers as words with the system's number formatter: "42" → "сорок два".
public enum NumberWords {
    /// Standalone whole numbers only: versions, decimals, times, dates and codes like "007" stay as they are.
    static let number = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}.,:/\\-])[1-9]\\d{0,8}(?![\\p{L}\\p{N}]|[.,:/\\-]\\d)|(?<![\\p{L}\\p{N}.,:/\\-])0(?![\\p{L}\\p{N}]|[.,:/\\-]\\d)")

    public static func apply(_ text: String, language: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: language)
        var result = text
        let matches = number.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result), let value = Int(result[range]),
                  let words = formatter.string(from: NSNumber(value: value)) else { continue }
            result.replaceSubrange(range, with: words)
        }
        return result
    }
}
