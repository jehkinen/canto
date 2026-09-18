import Foundation

/// Turns dictated numerals into digits ("двадцать пять" → "25") and amounts into currency
/// symbols ("50 долларов" → "$50"). Russian and English.
public enum SpokenNumbers {
    // MARK: Words to digits

    /// Number words that stay words when they are the only number around: on its own "один"/"one"
    /// is usually an article or a pronoun ("одна из них"), not a quantity.
    static let standaloneExceptions: Set<String> = ["один", "одна", "одно", "одну", "одни", "one"]

    static let units: [String: Int] = [
        "ноль": 0, "нуль": 0, "один": 1, "одна": 1, "одно": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4,
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
            // A numerator already in digits: "1 пятая", "2 трети".
            if isDigits(pieces[index].word), let fraction = fraction(pieces, from: index, to: index) {
                result += fraction.text
                index = fraction.next
                continue
            }
            guard startsNumber(pieces, at: index) else {
                result += pieces[index].word + pieces[index].separator
                index += 1
                continue
            }
            // After a decimal point a multiplier is not part of the digits: "1 точка 5 миллиона" is 1.5 million.
            let isFractionPart = followsDecimalPoint(pieces, at: index)
            var end = index
            while end + 1 < pieces.count, continues(pieces, from: end),
                  !(isFractionPart && multipliers[pieces[end + 1].word.lowercased()] != nil) {
                end += 1
            }
            if let decimal = wholeAndTenths(pieces, from: index, to: end) ?? fraction(pieces, from: index, to: end) {
                result += decimal.text
                index = decimal.next
                continue
            }
            let run = Array(pieces[index...end])
            if run.count == 1, standaloneExceptions.contains(run[0].word.lowercased()), !hasNumberNeighbour(pieces, from: index, to: end) {
                result += run[0].word + run[0].separator
            } else {
                let next = end + 1 < pieces.count ? pieces[end + 1].word : ""
                result += render(run, beforeOrdinal: isOrdinal(next))
            }
            index = end + 1
        }
        return joinDecimals(result)
    }

    static func isOrdinal(_ word: String) -> Bool {
        !word.isEmpty && ordinal.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) != nil
    }

    private static func isNumberWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        return units[lowered] != nil || multipliers[lowered] != nil
    }

    static func isNumeric(_ word: String) -> Bool {
        isNumberWord(word) || isDigits(word)
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
        return !followsDecimalPoint(pieces, at: index)
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
        return parts.map(\.text).joined()
    }

    /// The value of a run that is one number ("двадцать одна"), not several ("пять шесть").
    static func singleValue(_ run: ArraySlice<Piece>) -> Int? {
        var builder = NumberBuilder()
        for piece in run {
            let lowered = piece.word.lowercased()
            if isDigits(piece.word), builder.words == 0, let value = Int(piece.word) {
                builder.seed(piece.word, value: value)
                continue
            }
            guard isNumberWord(lowered) else { return nil }
            let value = units[lowered] ?? multipliers[lowered] ?? 0
            guard builder.accepts(lowered, value: value) else { return nil }
            builder.add(piece.word, lowered: lowered, value: value)
        }
        return builder.value
    }

    // MARK: Neighbours, decimals and fractions

    /// Words that link two numbers: "один и пять", "один или два", "один точка пять".
    static let links: Set<String> = ["и", "или", "либо", "and", "or", "точка", "запятая", "point"]

    /// Spoken decimal points and what they are written as.
    static let decimalPoints: [String: String] = ["точка": ".", "point": ".", "запятая": ","]

    private static func isSpace(_ separator: String) -> Bool {
        !separator.isEmpty && separator.allSatisfy { $0 == " " || $0 == "\u{00A0}" }
    }

    /// Punctuation that still keeps two numbers together: "один, два", "один-два", "1/2".
    private static func isListSeparator(_ separator: String) -> Bool {
        let trimmed = separator.trimmingCharacters(in: .whitespaces)
        return isSpace(separator) || [",", "-", "–", "—", "/"].contains(trimmed)
    }

    /// Whether "один" at `start...end` has another number next to it: "один и пять", "один, два".
    private static func hasNumberNeighbour(_ pieces: [Piece], from start: Int, to end: Int) -> Bool {
        func startsLowercase(_ word: String) -> Bool { word.first.map { !$0.isUppercase } ?? false }
        if end + 1 < pieces.count {
            let next = pieces[end + 1].word
            if isListSeparator(pieces[end].separator), isNumeric(next) { return true }
            if isSpace(pieces[end].separator), links.contains(next.lowercased()), end + 2 < pieces.count,
               isSpace(pieces[end + 1].separator), isNumeric(pieces[end + 2].word),
               // "пять точка Один из них": a capital starts a new sentence.
               decimalPoints[next.lowercased()] == nil || startsLowercase(pieces[end + 2].word) {
                return true
            }
        }
        if start > 0 {
            let previous = pieces[start - 1]
            if isListSeparator(previous.separator), isNumeric(previous.word) { return true }
            if isSpace(previous.separator), links.contains(previous.word.lowercased()), start > 1,
               isSpace(pieces[start - 2].separator), isNumeric(pieces[start - 2].word) {
                return true
            }
        }
        return false
    }

    /// The run at `index` comes right after a spoken decimal point: "пять" in "один точка пять".
    private static func followsDecimalPoint(_ pieces: [Piece], at index: Int) -> Bool {
        guard index > 1 else { return false }
        return decimalPoints[pieces[index - 1].word.lowercased()] != nil && isSpace(pieces[index - 1].separator)
            && isNumeric(pieces[index - 2].word) && isSpace(pieces[index - 2].separator)
    }

    /// Whether the "точка" or "запятая" between `before` and `after` is a decimal point, so spoken
    /// punctuation leaves it for the numbers: "один точка пять" is 1.5, "два точка ноль точка один"
    /// is 2.0.1. Commas between several numbers are a list: "один запятая два запятая три".
    static func isDecimalPoint(_ word: String, before: some StringProtocol, after: some StringProtocol) -> Bool {
        let left = split(String(before))
        let right = split(String(after)).drop { $0.word.isEmpty }.map { $0 }
        guard let last = left.last, isNumeric(last.word), last.separator.allSatisfy(\.isWhitespace),
              let first = right.first, isNumeric(first.word), first.word.first?.isUppercase != true else { return false }
        guard word.lowercased() == "запятая" else { return true }

        func joinsAnotherNumber(_ separator: String, _ word: String, then next: Piece?) -> Bool {
            if separator.trimmingCharacters(in: .whitespaces) == ",", isNumeric(word) { return true }
            guard isSpace(separator), word.lowercased() == "запятая", let next else { return false }
            return isNumeric(next.word)
        }
        var start = left.count - 1
        while start > 0, isSpace(left[start - 1].separator), isNumeric(left[start - 1].word) { start -= 1 }
        if start > 0 {
            let previous = left[start - 1]
            // Before the number: "три запятая" or "три, ".
            if previous.separator.trimmingCharacters(in: .whitespaces) == ",", isNumeric(previous.word) { return false }
            if isSpace(previous.separator), previous.word.lowercased() == "запятая", start > 1, isNumeric(left[start - 2].word) {
                return false
            }
        }
        var end = 0
        while end + 1 < right.count, isSpace(right[end].separator), isNumeric(right[end + 1].word) { end += 1 }
        if end + 1 < right.count,
           joinsAnotherNumber(right[end].separator, right[end + 1].word, then: end + 2 < right.count ? right[end + 2] : nil) {
            return false
        }
        return true
    }

    /// "1 точка 5" → "1.5", "2 точка 0 точка 1" → "2.0.1", "3 запятая 14" → "3,14": the digits after
    /// the point, spoken as separate numbers ("ноль пять"), are written together.
    static let decimalExpression = try! NSRegularExpression(pattern: """
        (?<![\\p{L}\\p{N}.,])\\d+(?:[ \u{00A0}](?:точка|point)[ \u{00A0}]\\d+(?:[ \u{00A0}]\\d+)*)+(?![\\p{L}\\p{N}])\
        |(?<![\\p{L}\\p{N}.,])\\d+[ \u{00A0}]запятая[ \u{00A0}]\\d+(?:[ \u{00A0}]\\d+)*(?![\\p{L}\\p{N}])
        """, options: [.caseInsensitive])

    private static func joinDecimals(_ text: String) -> String {
        var result = text
        for match in decimalExpression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            var joined = ""
            for piece in split(String(result[range])) {
                if let point = decimalPoints[piece.word.lowercased()] { joined += point } else { joined += piece.word }
            }
            result.replaceSubrange(range, with: joined)
        }
        return result
    }

    /// "одна целая пять десятых" → "1,5", "две целых двадцать пять сотых" → "2,25".
    private static func wholeAndTenths(_ pieces: [Piece], from start: Int, to end: Int) -> (text: String, next: Int)? {
        guard end + 2 < pieces.count, let whole = singleValue(pieces[start...end]), isSpace(pieces[end].separator),
              ["целая", "целых", "целую", "целой"].contains(pieces[end + 1].word.lowercased()),
              isSpace(pieces[end + 1].separator), startsNumber(pieces, at: end + 2) else { return nil }
        var fractionEnd = end + 2
        while fractionEnd + 1 < pieces.count, continues(pieces, from: fractionEnd) { fractionEnd += 1 }
        guard fractionEnd + 1 < pieces.count, isSpace(pieces[fractionEnd].separator),
              let tenths = singleValue(pieces[(end + 2)...fractionEnd]) else { return nil }
        let unit = pieces[fractionEnd + 1].word.lowercased()
        let places: Int
        if unit.hasPrefix("десят") { places = 1 } else if unit.hasPrefix("сот") { places = 2 } else if unit.hasPrefix("тысячн") { places = 3 } else {
            return nil
        }
        guard ["ая", "ых", "ую", "ой"].contains(where: unit.hasSuffix) else { return nil }
        let digits = String(tenths)
        guard digits.count <= places else { return nil }
        let text = "\(whole),\(String(repeating: "0", count: places - digits.count))\(digits)" + pieces[fractionEnd + 1].separator
        return (text, fractionEnd + 2)
    }

    /// Denominators: "пятая" after "одна", "пятых" after "две"…"десять", "трети", "fifth(s)".
    static let singularDenominators: [String: Int] = {
        var result: [String: Int] = ["третья": 3, "третью": 3, "треть": 3, "четверть": 4,
                                     "half": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
                                     "eighth": 8, "ninth": 9, "tenth": 10]
        for (stem, value) in denominatorStems {
            result[stem + "ая"] = value
            result[stem + "ую"] = value
        }
        return result
    }()

    static let pluralDenominators: [String: Int] = {
        var result: [String: Int] = ["третьих": 3, "трети": 3, "третей": 3, "четверти": 4, "четвертей": 4,
                                     "thirds": 3, "fourths": 4, "fifths": 5, "sixths": 6, "sevenths": 7,
                                     "eighths": 8, "ninths": 9, "tenths": 10]
        for (stem, value) in denominatorStems { result[stem + "ых"] = value }
        return result
    }()

    static let denominatorStems: [(String, Int)] = [
        ("втор", 2), ("четверт", 4), ("четвёрт", 4), ("пят", 5), ("шест", 6), ("седьм", 7), ("восьм", 8),
        ("девят", 9), ("десят", 10), ("сот", 100), ("тысячн", 1_000),
    ]

    static let singularNumerators: Set<String> = ["одна", "одну", "one"]
    static let pluralNumerators: Set<String> = [
        "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять",
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    ]

    /// "одна пятая" → "1/5", "две трети" → "2/3", "three fifths" → "3/5". The numerator's form must
    /// agree with the denominator, so the ordinal "двадцать пятая" stays a word.
    private static func fraction(_ pieces: [Piece], from start: Int, to end: Int) -> (text: String, next: Int)? {
        guard end + 1 < pieces.count, isSpace(pieces[end].separator), let numerator = singleValue(pieces[start...end]) else { return nil }
        let last = pieces[end].word.lowercased()
        let word = pieces[end + 1].word.lowercased()
        let isSingular: Bool
        if isDigits(last) {
            isSingular = numerator % 10 == 1 && numerator % 100 != 11
        } else if singularNumerators.contains(last) {
            isSingular = true
        } else if pluralNumerators.contains(last) {
            isSingular = false
        } else {
            return nil
        }
        guard let denominator = isSingular ? singularDenominators[word] : pluralDenominators[word],
              last.allSatisfy(\.isASCII) == word.allSatisfy(\.isASCII) || isDigits(last) else { return nil }
        return ("\(numerator)/\(denominator)" + pieces[end + 1].separator, end + 2)
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
