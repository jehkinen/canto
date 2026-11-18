import Foundation
import Testing
@testable import CantoCore

struct StatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 10))!
    }

    @Test(arguments: [
        ("Привет, как дела?", 3),
        ("900 млн параметров", 3),
        ("   ", 0),
        ("— … -", 0),
        ("one", 1),
    ])
    func countsWords(text: String, expected: Int) {
        #expect(DictationStats.wordCount(of: text) == expected)
    }

    @Test func addsUpByDayAndInTotal() {
        var stats = DictationStats()
        stats.add(words: 10, characters: 50, seconds: 8, at: day(1), calendar: calendar)
        stats.add(words: 5, characters: 25, seconds: 4, at: day(1), calendar: calendar)
        stats.add(words: 7, characters: 30, seconds: 6, at: day(2), calendar: calendar)

        #expect(stats.phrases == 3)
        #expect(stats.words == 22)
        #expect(stats.seconds == 18)
        #expect(stats.firstDictation == day(1))
        #expect(stats.days.count == 2)
        #expect(stats.today(day(1), calendar: calendar).words == 15)
        #expect(stats.today(day(2), calendar: calendar).phrases == 1)
        // A day without dictation has its own empty entry.
        #expect(stats.today(day(3), calendar: calendar).words == 0)
    }

    @Test func emptyPhrasesAreNotCounted() {
        var stats = DictationStats()
        stats.add(words: 0, characters: 0, seconds: 3, at: day(1), calendar: calendar)
        #expect(stats.phrases == 0)
        #expect(stats.days.isEmpty)
    }

    @Test func recentDaysFillTheGaps() {
        var stats = DictationStats()
        stats.add(words: 4, characters: 20, seconds: 2, at: day(1), calendar: calendar)
        stats.add(words: 6, characters: 30, seconds: 3, at: day(3), calendar: calendar)
        let recent = stats.recentDays(3, until: day(3), calendar: calendar)
        #expect(recent.map(\.words) == [4, 0, 6])
        #expect(recent.first?.date == calendar.startOfDay(for: day(1)))
    }

    @Test func keepsOnlyTheLastDaysOneByOne() {
        var stats = DictationStats()
        for index in 0..<(DictationStats.keptDays + 10) {
            let date = calendar.date(byAdding: .day, value: index, to: day(1))!
            stats.add(words: 1, characters: 5, seconds: 1, at: date, calendar: calendar)
        }
        #expect(stats.days.count == DictationStats.keptDays)
        // The totals still know about every phrase.
        #expect(stats.phrases == DictationStats.keptDays + 10)
    }

    @Test func savesAndLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StatsStore(fileURL: directory.appendingPathComponent("stats.json"))
        #expect(store.load() == DictationStats())

        var stats = DictationStats()
        stats.add(words: 3, characters: 12, seconds: 2, at: day(1), calendar: calendar)
        try store.save(stats)
        #expect(store.load() == stats)

        // A file that can not be read starts the counters over instead of failing.
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load() == DictationStats())
    }
}
