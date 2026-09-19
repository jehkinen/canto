import Foundation

/// Writes whole numbers as words with the system's number formatter: "42" → "сорок два".
public enum NumberWords {
    /// Standalone whole numbers only, "1 000" grouped by spaces included: versions, decimals, times,
    /// dates, codes like "007" and forms like "5-й" or "10-летие" stay as they are.
    static let number = try! NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}.,:/\\-])(?:[1-9]\\d{0,2}(?:[ \\u00A0]\\d{3})+|[1-9]\\d{0,8}|0)(?![\\p{L}\\p{N}]|[.,:/\\-]\\d|-\\p{L})"
    )

    public static func apply(_ text: String, language: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: language)
        var result = text
        let matches = number.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result), let value = Int(result[range].filter(\.isNumber)),
                  let words = formatter.string(from: NSNumber(value: value)) else { continue }
            result.replaceSubrange(range, with: words)
        }
        return result
    }
}
