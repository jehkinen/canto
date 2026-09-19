import Testing
@testable import CantoCore

struct PhraseJoinerTests {
    @Test(arguments: [
        ("It will be.", "And then it was released.", " "),
        ("it will be", "and then", " "),
        ("Hello", ", and then", ""),
        ("Wait", "…", ""),
        ("Done.\n", "Next", ""),
        ("Open (", "this", ""),
        ("", "First", ""),
        ("Last", "", ""),
        ("今日は晴れです。", "明日は雨です。", ""),
        ("Привет.", "Как дела?", " "),
    ])
    func separatesPhrasesWithASpaceOnlyWhereOneBelongs(previous: String, next: String, separator: String) {
        #expect(PhraseJoiner.separator(after: previous, before: next) == separator)
    }
}
