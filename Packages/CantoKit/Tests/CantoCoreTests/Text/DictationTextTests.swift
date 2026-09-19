import Testing
@testable import CantoCore

/// Cases found in the September 2026 code review: each one changed what the user said.
struct DictationTextTests {
    @Test(arguments: [
        ("Я купил хлеб. Хлеб был свежий.", "Я купил хлеб. Хлеб был свежий."),
        ("I went to the store. The store was closed.", "I went to the store. The store was closed."),
        ("мы мы пойдём", "Мы пойдём"),
        ("5 минут назад звонил", "5 минут назад звонил"),
        ("5-й этаж", "5-й этаж"),
        ("https://example.com открой", "https://example.com открой"),
        (".gitignore поправь", ".gitignore поправь"),
        ("iPhone сломался", "iPhone сломался"),
        ("«привет» сказал он", "«Привет» сказал он"),
        ("добавь это в .gitignore", "Добавь это в .gitignore"),
        ("пишу на .NET и ASP.NET", "Пишу на .NET и ASP.NET"),
        ("U.S.A. и U.K.", "U.S.A. и U.K."),
        ("по этим начислениям будет.А выпущен", "По этим начислениям будет. А выпущен"),
        ("привет , как дела ?", "Привет, как дела?"),
    ])
    func basicCleanupKeepsWhatWasSaid(input: String, expected: String) {
        #expect(TextCleanup.basic(input) == expected)
    }

    @Test(arguments: [
        ("Встреча девятого мая точка потом обед", "Встреча девятого мая. Потом обед"),
        ("Я вернулся из Китая точка Было круто", "Я вернулся из Китая. Было круто"),
        ("до мая запятая потом отпуск", "до мая, потом отпуск"),
        ("Это стартовая точка проекта", "Это стартовая точка проекта"),
        ("последняя точка маршрута", "последняя точка маршрута"),
    ])
    func punctuationCommandsAfterNounsInAya(input: String, expected: String) {
        #expect(TextCleanup.applySpokenPunctuation(input) == expected)
    }

    @Test(arguments: ["Oh shit.", "What the fuck.", "Got him. Holy shit.", "I'm going to get you."])
    func realExclamationsAreNotHallucinations(text: String) {
        #expect(TextCleanup.removeWhisperArtifacts(text) == text)
    }

    @Test func subtitleFillerIsStillRemoved() {
        #expect(TextCleanup.removeWhisperArtifacts("Hello there. Thanks for watching.") == "Hello there.")
    }

    @Test(arguments: [
        ("Цена 1 000 рублей", "Цена одна тысяча рублей"),
        ("это 10 000 человек", "это десять тысяч человек"),
        ("5-й этаж", "5-й этаж"),
        ("2-го числа", "2-го числа"),
        ("10-летие", "10-летие"),
        ("пять-шесть 5 раз", "пять-шесть пять раз"),
    ])
    func numbersAsRussianWords(input: String, expected: String) {
        #expect(NumberWords.apply(input, language: "ru") == expected)
    }

    @Test(arguments: [
        ("I phone my mom every day", "I phone my mom every day"),
        ("iphone сломался", "iPhone сломался"),
        ("Iphone сломался", "iPhone сломался"),
        ("I-phone", "iPhone"),
        ("Macos обновился", "macOS обновился"),
        ("Main ветка", "Main ветка"),
        ("GPT 4 ответил", "GPT-4 ответил"),
    ])
    func vocabularyKeepsBrandSpelling(input: String, expected: String) {
        #expect(Vocabulary.apply(input, terms: ["iPhone", "macOS", "main", "GPT-4"]) == expected)
    }

    @Test(arguments: [
        ("<think>The user wants a cleanup.</think>\nПривет, как дела?", "Привет, как дела?"),
        ("<think>still thinking", ""),
        ("```Готово```", "Готово"),
        ("```\nГотово\n```", "Готово"),
    ])
    func sanitizesModelReplies(reply: String, expected: String) {
        #expect(AIRewriter.sanitize(reply) == expected)
    }
}
