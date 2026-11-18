import Foundation

/// How much was dictated, in numbers only: no text is ever kept here, so the counters work the
/// same when the history is switched off.
public struct DictationStats: Codable, Equatable, Sendable {
    /// A day with its numbers; days without dictation are not stored.
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public var date: Date
        public var phrases: Int
        public var words: Int
        public var characters: Int
        public var seconds: TimeInterval

        public var id: Date { date }

        public init(date: Date, phrases: Int = 0, words: Int = 0, characters: Int = 0, seconds: TimeInterval = 0) {
            self.date = date
            self.phrases = phrases
            self.words = words
            self.characters = characters
            self.seconds = seconds
        }
    }

    /// Since the first dictation, including days no longer kept one by one.
    public var phrases = 0
    public var words = 0
    public var characters = 0
    public var seconds: TimeInterval = 0
    public var firstDictation: Date?
    /// Recent days, oldest first.
    public var days: [Day] = []

    /// Days kept one by one; older ones live on in the totals.
    static let keptDays = 90

    public init() {}

    public mutating func add(words: Int, characters: Int, seconds: TimeInterval, at moment: Date = Date(),
                             calendar: Calendar = .current) {
        guard words > 0 || characters > 0 else { return }
        phrases += 1
        self.words += words
        self.characters += characters
        self.seconds += seconds
        if firstDictation == nil { firstDictation = moment }

        let day = calendar.startOfDay(for: moment)
        if let index = days.lastIndex(where: { $0.date == day }) {
            days[index].phrases += 1
            days[index].words += words
            days[index].characters += characters
            days[index].seconds += seconds
        } else {
            days.append(Day(date: day, phrases: 1, words: words, characters: characters, seconds: seconds))
            days.sort { $0.date < $1.date }
        }
        if days.count > Self.keptDays {
            days.removeFirst(days.count - Self.keptDays)
        }
    }

    public func today(_ moment: Date = Date(), calendar: Calendar = .current) -> Day {
        let day = calendar.startOfDay(for: moment)
        return days.last { $0.date == day } ?? Day(date: day)
    }

    /// The last `count` days, oldest first, with empty days filled in, for a small chart.
    public func recentDays(_ count: Int, until moment: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let last = calendar.startOfDay(for: moment)
        return (0..<count).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: last) else { return nil }
            return days.last { $0.date == date } ?? Day(date: date)
        }
    }

    /// Words of a phrase: anything separated by spaces that has a letter or a digit in it.
    public static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace)
            .count { $0.contains { $0.isLetter || $0.isNumber } }
    }
}

/// Reads and writes the counters as JSON next to the other Canto data.
public struct StatsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> DictationStats {
        guard let data = try? Data(contentsOf: fileURL) else { return DictationStats() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(DictationStats.self, from: data)) ?? DictationStats()
    }

    public func save(_ stats: DictationStats) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stats).write(to: fileURL, options: .atomic)
    }
}
