import Foundation

/// Millions and billions read better short: "девятьсот миллионов" → "900 млн", "полтора миллиарда"
/// → "1,5 млрд". Only numbers the speaker said in words are shortened, and only when the multiplier
/// ends the number: "миллион двести тысяч" stays a plain number.
public enum LargeNumbers {
    public static func abbreviate(_ text: String) -> String {
        var pieces = SpokenNumbers.split(text)
        var index = pieces.count - 1
        while index >= 0 {
            defer { index -= 1 }
            guard let scale = scales[pieces[index].word.lowercased()],
                  endsTheNumber(pieces, at: index),
                  let amount = quantity(in: pieces, before: index, scale: scale) else { continue }
            pieces[index].word = format(amount.value, english: scale.isEnglish) + " " + scale.short
            pieces.removeSubrange(amount.start..<index)
            index = amount.start
        }
        return pieces.map { $0.word + $0.separator }.joined()
    }

    private struct Scale {
        var short: String
        var isEnglish: Bool
        /// "миллион рублей" means one of them; "миллионы людей" is not a number.
        var standsAlone: Bool
    }

    private static let scales: [String: Scale] = {
        var table: [String: Scale] = [:]
        for (stem, short) in [("миллион", "млн"), ("миллиард", "млрд"), ("триллион", "трлн")] {
            for ending in ["", "а", "у", "ом", "е", "ов", "ам", "ами", "ах"] {
                table[stem + ending] = Scale(short: short, isEnglish: false, standsAlone: ending.isEmpty)
            }
        }
        for word in ["million", "billion", "trillion"] {
            table[word] = Scale(short: word, isEnglish: true, standsAlone: false)
            table[word + "s"] = Scale(short: word, isEnglish: true, standsAlone: false)
        }
        return table
    }()

    /// The multiplier is the last word of the number: in "миллион двести тысяч" it is not.
    private static func endsTheNumber(_ pieces: [SpokenNumbers.Piece], at index: Int) -> Bool {
        guard index + 1 < pieces.count else { return true }
        return !isPartOfNumber(pieces[index + 1].word)
    }

    private static func isPartOfNumber(_ word: String) -> Bool {
        let lowered = word.lowercased()
        return SpokenNumbers.units[lowered] != nil || (SpokenNumbers.multipliers[lowered] ?? .max) <= 100
            || (!word.isEmpty && word.allSatisfy(\.isNumber))
    }

    /// How many of them were said, and where that number starts.
    private static func quantity(in pieces: [SpokenNumbers.Piece], before index: Int, scale: Scale)
        -> (value: Double, start: Int)? {
        var end = index
        var half = false
        // "два с половиной миллиона", "two and a half million".
        if scale.isEnglish {
            if end >= 3, words(pieces, end - 3, end) == ["and", "a", "half"] {
                half = true
                end -= 3
            }
        } else if end >= 2, words(pieces, end - 2, end) == ["с", "половиной"] {
            half = true
            end -= 2
        }
        if end >= 1, ["полтора", "полторы"].contains(pieces[end - 1].word.lowercased()), !half {
            return (1.5, end - 1)
        }
        var start = end
        while start > 0, isPartOfNumber(pieces[start - 1].word) {
            start -= 1
        }
        guard start < end else {
            // Nothing before the multiplier: "миллион рублей" is one of them, "миллионы людей" is not.
            return half || !scale.standsAlone ? nil : (1, index)
        }
        let spoken = words(pieces, start, end).joined(separator: " ")
        guard let whole = Int(SpokenNumbers.toDigits(spoken)) else { return nil }
        return (Double(whole) + (half ? 0.5 : 0), start)
    }

    private static func words(_ pieces: [SpokenNumbers.Piece], _ start: Int, _ end: Int) -> [String] {
        pieces[start..<end].map { $0.word.lowercased() }
    }

    private static func format(_ value: Double, english: Bool) -> String {
        guard value != value.rounded(.down) else { return String(Int(value)) }
        return String(Int(value)) + (english ? "." : ",") + "5"
    }
}
