import Foundation

/// The words the text rules need for one language, kept out of the code: add a language by adding
/// a JSON file to `Languages`. The rules themselves (in `TextCleanup`) are the same for every language.
public struct LanguagePack: Decodable, Sendable {
    public var code: String
    /// Whole sentences Whisper writes on silence or noise, lowercased, without punctuation.
    public var phantomSentences: [String] = []
    /// Regular expressions for subtitle credits that open a sentence: "Субтитры делал …".
    public var creditPatterns: [String] = []
    /// Regular expression fragments for sounds Whisper puts in parentheses: "(музыка)".
    public var soundWords: [String] = []
    /// Words people repeat on purpose ("да да", "да да да"), which the repeat and loop cleanups keep.
    public var intentionalRepeats: [String] = []
    /// Number words `SpokenNumbers` does not read yet (it knows Russian and English), so the repeat
    /// cleanups leave a number said digit by digit alone: "חמש חמש חמש".
    public var numberWords: [String] = []
    /// Named word lists that punctuation commands refer to as "@name".
    public var wordSets: [String: [String]] = [:]
    public var punctuation: [Command] = []

    /// A spoken punctuation command: "запятая" → ",".
    public struct Command: Decodable, Sendable {
        public var words: String
        public var symbol: String
        /// Words before the command that make it an ordinary noun: "стартовая точка", "the trial period".
        public var notAfter: [String] = []
        public var notAfterEndings: [String] = []
        /// Regular expression fragments for words after it that make a set phrase: "точка зрения".
        public var notBefore: [String] = []
        /// Between two numbers the word is a decimal point: "один точка пять".
        public var decimalPoint = false

        enum CodingKeys: String, CodingKey {
            case words, symbol, notAfter, notAfterEndings, notBefore, decimalPoint
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            words = try c.decode(String.self, forKey: .words)
            symbol = try c.decode(String.self, forKey: .symbol)
            notAfter = try c.decodeIfPresent([String].self, forKey: .notAfter) ?? []
            notAfterEndings = try c.decodeIfPresent([String].self, forKey: .notAfterEndings) ?? []
            notBefore = try c.decodeIfPresent([String].self, forKey: .notBefore) ?? []
            decimalPoint = try c.decodeIfPresent(Bool.self, forKey: .decimalPoint) ?? false
        }
    }

    enum CodingKeys: String, CodingKey {
        case code, phantomSentences, creditPatterns, soundWords, intentionalRepeats, numberWords, wordSets, punctuation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        phantomSentences = try c.decodeIfPresent([String].self, forKey: .phantomSentences) ?? []
        creditPatterns = try c.decodeIfPresent([String].self, forKey: .creditPatterns) ?? []
        soundWords = try c.decodeIfPresent([String].self, forKey: .soundWords) ?? []
        intentionalRepeats = try c.decodeIfPresent([String].self, forKey: .intentionalRepeats) ?? []
        numberWords = try c.decodeIfPresent([String].self, forKey: .numberWords) ?? []
        wordSets = try c.decodeIfPresent([String: [String]].self, forKey: .wordSets) ?? [:]
        punctuation = try c.decodeIfPresent([Command].self, forKey: .punctuation) ?? []
    }

    /// The words a command's `notAfter` stands for, with "@name" replaced by that word set.
    func expand(_ words: [String]) -> Set<String> {
        Set(words.flatMap { $0.hasPrefix("@") ? wordSets[String($0.dropFirst())] ?? [] : [$0] })
    }

    /// The languages that come with Canto. Russian first: its commands are matched before English ones.
    public static let bundled: [LanguagePack] = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Languages") ?? []
        let packs = urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(LanguagePack.self, from: $0) } }
        let order = ["ru", "en", "he"]
        return packs.sorted { (order.firstIndex(of: $0.code) ?? order.count, $0.code) < (order.firstIndex(of: $1.code) ?? order.count, $1.code) }
    }()
}
