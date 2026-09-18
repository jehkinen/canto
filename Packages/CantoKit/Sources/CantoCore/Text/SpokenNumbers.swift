import Foundation

/// Turns dictated numerals into digits ("двадцать пять" → "25") and amounts into currency
/// symbols ("50 долларов" → "$50"). Russian and English.
public enum SpokenNumbers {
    // MARK: Words to digits

    /// Number words that stay words when they are the only number around: on its own "один"/"one"
    /// is usually an article or a pronoun ("одна из них"), not a quantity.
    static let standaloneExceptions: Set<String> = ["один", "одна", "одно", "одни", "one"]

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

    /// Words that multiply the number before them.
    static let multipliers: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
        "тысяча": 1_000, "тысячи": 1_000, "тысяч": 1_000, "тысячу": 1_000,
        "миллион": 1_000_000, "миллиона": 1_000_000, "миллионов": 1_000_000,
        "миллиард": 1_000_000_000, "миллиарда": 1_000_000_000, "миллиардов": 1_000_000_000,
    ]

    /// Multipliers that mean one of them when they come alone: "тысяча рублей" is 1000, while
    /// "тысячи людей" and "a thousand people" are not a number to write in digits.
    static let standaloneMultipliers: Set<String> = ["тысяча", "тысячу", "миллион", "миллиард"]

    /// Ordinals end a number spelled in words: "двадцать первый век" and "в две тысячи двадцать
    /// шестом году" stay as they are instead of becoming "20 первый" or "2020 шестом".
    static let ordinal = try! NSRegularExpression(pattern: """
        ^(?:трет(?:ий|ья|ье|ьи|ьего|ьему|ьим|ьем|ьих|ьей|ью)\
        |(?:перв|втор|четв[её]рт|пят|шест|седьм|восьм|девят|десят|одиннадцат|двенадцат|тринадцат|\
        четырнадцат|пятнадцат|шестнадцат|семнадцат|восемнадцат|девятнадцат|двадцат|тридцат|сороков|\
        пятидесят|шестидесят|семидесят|восьмидесят|девяност|сот|тысячн|миллионн)\
        (?:ый|ой|ая|ое|ые|ого|ому|ым|ом|ых|ыми|ую)\
        |first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|\\p{L}+teenth\
        |\\p{L}+tieth|hundredth|thousandth|millionth)$
        """, options: [.caseInsensitive])

    public static func toDigits(_ text: String) -> String {
        let pieces = split(text)
        var result = ""
        var index = 0
        while index < pieces.count {
            guard startsNumber(pieces, at: index) else {
                result += pieces[index].word + pieces[index].separator
                index += 1
                continue
            }
            var end = index
            while end + 1 < pieces.count, continues(pieces, from: end) { end += 1 }
            let next = end + 1 < pieces.count ? pieces[end + 1].word : ""
            result += render(Array(pieces[index...end]), beforeOrdinal: isOrdinal(next))
            index = end + 1
        }
        return result
    }

    static func isOrdinal(_ word: String) -> Bool {
        !word.isEmpty && ordinal.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) != nil
    }

    private static func isNumberWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        return units[lowered] != nil || multipliers[lowered] != nil
    }

    private static func isDigits(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy(\.isASCII) && word.allSatisfy(\.isNumber)
    }

    /// A number in words starts here, or digits with a multiplier ("5 тысяч"), but not the
    /// fraction of a decimal ("2,5 миллиона").
    private static func startsNumber(_ pieces: [Piece], at index: Int) -> Bool {
        if isNumberWord(pieces[index].word) { return true }
        guard isDigits(pieces[index].word), pieces[index].separator == " ", index + 1 < pieces.count,
              multipliers[pieces[index + 1].word.lowercased()] != nil else { return false }
        if index > 0, isDigits(pieces[index - 1].word), [",", "."].contains(pieces[index - 1].separator) { return false }
        return true
    }

    /// Whether the word after `index` belongs to the same run of number words.
    private static func continues(_ pieces: [Piece], from index: Int) -> Bool {
        let separator = pieces[index].separator
        let next = pieces[index + 1].word
        let lowered = next.lowercased()
        if separator.allSatisfy({ $0 == " " || $0 == "\u{00A0}" }), !separator.isEmpty {
            if isNumberWord(next) { return true }
            // "one hundred and twenty": "and" stays in the run only when a number word follows.
            if lowered == "and", index + 2 < pieces.count, pieces[index + 1].separator == " " {
                return isNumberWord(pieces[index + 2].word)
            }
            if pieces[index].word.lowercased() == "and" { return isNumberWord(next) }
            return false
        }
        // "twenty-five", but not the Russian range "пять-шесть".
        if separator == "-", let tens = units[pieces[index].word.lowercased()], let unit = units[lowered],
           pieces[index].word.allSatisfy(\.isASCII), tens >= 20, tens < 100, tens % 10 == 0, (1...9).contains(unit) {
            return true
        }
        return false
    }

    /// Writes a run of number words as digits. Neighbours that do not add up to one number
    /// ("пять шесть семь") become separate numbers; "and" between them stays a word.
    private static func render(_ run: [Piece], beforeOrdinal: Bool) -> String {
        let original = run.map { $0.word + $0.separator }.joined()
        if beforeOrdinal { return original }

        var parts: [(text: String, isNumber: Bool)] = []
        var builder = NumberBuilder()
        var builderEnd = 0
        func finish() {
            guard builder.words > 0 else { return }
            parts.append((builder.value.map(String.init) ?? builder.spelled, builder.value != nil))
            parts[parts.count - 1].text += run[builderEnd].separator
            builder = NumberBuilder()
        }
        var index = 0
        while index < run.count {
            let word = run[index].word
            let lowered = word.lowercased()
            if lowered == "and" {
                let next = index + 1 < run.count ? run[index + 1].word.lowercased() : ""
                if builder.acceptsAnd, let value = units[next], value < 100, builder.accepts(next, value: value) {
                    index += 1
                    continue
                }
                finish()
                parts.append((word + run[index].separator, false))
                index += 1
                continue
            }
            if isDigits(word), let value = Int(word) {
                finish()
                builder.seed(word, value: value)
                builderEnd = index
                index += 1
                continue
            }
            let value = units[lowered] ?? multipliers[lowered] ?? 0
            if !builder.accepts(lowered, value: value) { finish() }
            if builder.accepts(lowered, value: value) {
                builder.add(word, lowered: lowered, value: value)
            } else {
                // A multiplier that can not start a number ("тысячи людей").
                parts.append((word + run[index].separator, false))
                index += 1
                continue
            }
            builderEnd = index
            index += 1
        }
        finish()

        // "один" alone is a word; next to other numbers ("восемь один два") it is a digit.
        if run.count == 1, standaloneExceptions.contains(run[0].word.lowercased()) { return original }
        return parts.map(\.text).joined()
    }

    /// Adds up number words place by place, and refuses a word that would not fit
    /// ("пять шесть" is two numbers, not eleven).
    struct NumberBuilder {
        var total = 0
        var group = 0
        var hasHundreds = false
        var hasTens = false
        var hasUnits = false
        var lastMultiplier = Int.max
        var words = 0
        var isEnglish = false
        var spelled = ""
        var closed = false

        var value: Int? { words > 0 ? total + group : nil }

        /// "and" may follow "hundred" or "thousand" in English.
        var acceptsAnd: Bool { isEnglish && (hasHundreds || lastMultiplier != Int.max) && !hasTens && !hasUnits }

        mutating func seed(_ digits: String, value: Int) {
            group = value
            hasHundreds = true
            hasTens = true
            hasUnits = true
            words = 1
            spelled = digits
        }

        func accepts(_ word: String, value: Int) -> Bool {
            guard !closed else { return false }
            if words > 0, word.allSatisfy(\.isASCII) != isEnglish { return false }
            if let multiplier = SpokenNumbers.multipliers[word] {
                if multiplier == 100 {
                    return (1...9).contains(group) && !hasHundreds && !hasTens
                }
                guard multiplier < lastMultiplier else { return false }
                if words == 0 { return SpokenNumbers.standaloneMultipliers.contains(word) }
                return group > 0
            }
            if value == 0 { return words == 0 }
            switch value {
            case 100...900: return !hasHundreds && !hasTens && !hasUnits && group == 0
            case 10...19: return !hasTens && !hasUnits
            case 20...90: return !hasTens && !hasUnits
            default: return !hasUnits
            }
        }

        mutating func add(_ original: String, lowered word: String, value: Int) {
            if words == 0 { isEnglish = word.allSatisfy(\.isASCII) }
            spelled += (spelled.isEmpty ? "" : " ") + original
            words += 1
            if let multiplier = SpokenNumbers.multipliers[word] {
                if multiplier == 100 {
                    group *= 100
                    hasHundreds = true
                    hasUnits = false
                    return
                }
                total += max(group, 1) * multiplier
                group = 0
                hasHundreds = false
                hasTens = false
                hasUnits = false
                lastMultiplier = multiplier
                return
            }
            group += value
            switch value {
            case 0: closed = true
            case 100...900: hasHundreds = true
            case 10...19: hasTens = true; hasUnits = true
            case 20...90: hasTens = true
            default: hasUnits = true
            }
        }
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
        let words = currency.words.map { word in
            // "руб." is an abbreviation, but a period before a capital letter or the end is the sentence's.
            word == "руб" ? "руб(?:\\.(?![ \\t]*(?:(?-i:\\p{Lu})|$)))?" : NSRegularExpression.escapedPattern(for: word)
        }.joined(separator: "|")
        // A whole amount: "50", "9.99", "2,5", "1 000" (grouped by spaces), not the tail of another number.
        let amount = "(?<![\\d.,])(\\d{1,3}(?:[ \u{00A0}]\\d{3})+|\\d+(?:[.,]\\d+)?)"
        let pattern = "\(amount)\\s+(?:\(words))(?![\\p{L}\\p{N}])"
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
