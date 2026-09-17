import Foundation

/// Turns dictated numerals into digits ("двадцать пять" → "25") and amounts into currency
/// symbols ("50 долларов" → "$50"). Russian and English.
public enum SpokenNumbers {
    // MARK: Words to digits

    /// Number words that stand on their own. "Один"/"one" is excluded: on its own it is usually
    /// an article or a pronoun ("одна из них"), not a quantity.
    static let standaloneExceptions: Set<String> = ["один", "одна", "одно", "одни", "one", "a", "an"]

    static let units: [String: Int] = [
        "ноль": 0, "нуль": 0, "один": 1, "одна": 1, "одно": 1, "два": 2, "две": 2, "три": 3, "четыре": 4,
        "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11,
        "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16,
        "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19, "двадцать": 20, "тридцать": 30,
        "сорок": 40, "пятьдесят": 50, "шестьдесят": 60, "семьдесят": 70, "восемьдесят": 80, "девяносто": 90,
        "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500, "шестьсот": 600,
        "семьсот": 700, "восемьсот": 800, "девятьсот": 900,
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Multipliers: "сто" as in "сто двадцать" is already a unit above; these multiply what came before.
    static let multipliers: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
        "тысяча": 1_000, "тысячи": 1_000, "тысяч": 1_000, "тысячу": 1_000,
        "миллион": 1_000_000, "миллиона": 1_000_000, "миллионов": 1_000_000,
        "миллиард": 1_000_000_000, "миллиарда": 1_000_000_000, "миллиардов": 1_000_000_000,
    ]

    /// Words that may sit inside a number without breaking it.
    static let connectors: Set<String> = ["and", "и"]

    public static func toDigits(_ text: String) -> String {
        let pieces = split(text)
        var result = ""
        var run: [String] = []
        var runSeparators: [String] = []

        func flush(_ trailing: String) {
            guard !run.isEmpty else { return }
            if let value = value(of: run) {
                result += "\(value)"
            } else {
                result += zip(run, runSeparators).map { $0 + $1 }.joined()
                result.removeLast(runSeparators.last?.count ?? 0)
            }
            result += trailing
            run = []
            runSeparators = []
        }

        for piece in pieces {
            let word = piece.word.lowercased()
            let isNumberWord = units[word] != nil || multipliers[word] != nil
            let isConnector = connectors.contains(word) && !run.isEmpty
            if isNumberWord || isConnector {
                run.append(piece.word)
                runSeparators.append(piece.separator)
                // A separator with a line break or punctuation other than a space ends the number.
                if piece.separator.contains(where: { !$0.isWhitespace }) || piece.separator.contains("\n") {
                    flush(piece.separator)
                }
            } else {
                flush(runSeparators.last ?? "")
                result += piece.word + piece.separator
            }
        }
        flush(runSeparators.last ?? "")
        return result
    }

    /// The number a run of words spells, or `nil` when it does not spell one.
    static func value(of words: [String]) -> Int? {
        let lowered = words.map { $0.lowercased() }.filter { !connectors.contains($0) }
        guard !lowered.isEmpty else { return nil }
        if lowered.count == 1, standaloneExceptions.contains(lowered[0]) { return nil }

        var total = 0
        var current = 0
        var sawValue = false
        for word in lowered {
            if let unit = units[word] {
                current += unit
                sawValue = true
            } else if let multiplier = multipliers[word] {
                current = max(current, 1) * multiplier
                if multiplier >= 1_000 {
                    total += current
                    current = 0
                }
                sawValue = true
            } else {
                return nil
            }
        }
        return sawValue ? total + current : nil
    }

    // MARK: Currency

    /// Amount words and how they are written: "$50" for dollars, "50 €" for euro.
    static let currencies: [(words: [String], symbol: String, prefix: Bool)] = [
        (["долларов", "доллара", "доллар", "баксов", "бакса", "бакс", "dollars", "dollar", "bucks", "buck", "usd"], "$", true),
        (["фунтов", "фунта", "фунт", "pounds", "pound", "gbp"], "£", true),
        (["евро", "euros", "euro", "eur"], "€", false),
        (["рублей", "рубля", "рубль", "руб", "roubles", "rubles", "rub"], "₽", false),
    ]

    static let currencyExpressions: [(NSRegularExpression, String)] = currencies.map { currency in
        let words = currency.words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "(\\d[\\d  ]*)\\s+(?:\(words))\\b\\.?"
        let template = currency.prefix ? "\(currency.symbol)$1" : "$1\u{00A0}\(currency.symbol)"
        return (try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), template)
    }

    public static func currencySymbols(_ text: String) -> String {
        var result = text
        for (expression, template) in currencyExpressions {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }

    // MARK: Splitting

    struct Piece {
        var word: String
        var separator: String
    }

    /// Splits into words and the characters between them, so the text can be rebuilt as it was.
    static func split(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var word = ""
        var separator = ""
        for character in text {
            if character.isLetter || character.isNumber {
                if !separator.isEmpty {
                    pieces.append(Piece(word: word, separator: separator))
                    word = ""
                    separator = ""
                }
                word.append(character)
            } else {
                separator.append(character)
            }
        }
        if !word.isEmpty || !separator.isEmpty {
            pieces.append(Piece(word: word, separator: separator))
        }
        return pieces
    }
}
