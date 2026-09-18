import Foundation
import Testing
@testable import CantoCore

/// Cases found in the September 2026 review: each one used to change or drop what the user said.
struct AuditRegressionTests {
    @Test(arguments: [
        ("пять шесть семь", "5 6 7"),
        ("восемь девять один шесть пять пять пять", "8 9 1 6 5 5 5"),
        ("в два три раза", "в 2 3 раза"),
        ("5 тысяч рублей", "5000 рублей"),
        ("2,5 миллиона", "2,5 миллиона"),
        ("twenty-five", "25"),
        ("one hundred twenty-three", "123"),
        ("десять и больше", "10 и больше"),
        ("I have two and she has three", "I have 2 and she has 3"),
        ("two and three", "2 and 3"),
        ("пять и шесть", "5 и 6"),
        ("в две тысячи двадцать шестом году", "в две тысячи двадцать шестом году"),
        ("двадцать первый век", "двадцать первый век"),
        ("пятью пять двадцать пять", "пятью 5 25"),
        ("тысячи людей", "тысячи людей"),
        ("тысяча рублей", "1000 рублей"),
        ("a thousand people", "a thousand people"),
        ("миллион двести тысяч", "1200000"),
        ("триста тысяч", "300000"),
        ("один из них", "один из них"),
        ("Пять человек", "5 человек"),
        ("пять-шесть", "5-6"),
    ])
    func numbers(input: String, expected: String) {
        #expect(SpokenNumbers.toDigits(input) == expected)
    }

    @Test(arguments: [
        ("Это стоит 50 долларов.", "Это стоит $50."),
        ("1000 рублей. Потом", "1000\u{00A0}₽. Потом"),
        ("9.99 dollars", "$9.99"),
        ("1,000 dollars", "$1,000"),
        ("2,5 доллара", "$2,5"),
        ("In 2024 50 dollars", "In 2024 $50"),
        ("1 000 рублей", "1 000\u{00A0}₽"),
        ("100 руб. за штуку", "100\u{00A0}₽ за штуку"),
        ("50 баксов в месяц", "$50 в месяц"),
    ])
    func currency(input: String, expected: String) {
        #expect(SpokenNumbers.currencySymbols(input) == expected)
    }

    @Test(arguments: [
        ("Я работаю редактором субтитров на ютубе.", "Я работаю редактором субтитров на ютубе."),
        ("Эти субтитры правильные, можно выкладывать.", "Эти субтитры правильные, можно выкладывать."),
        ("Субтитры создали автоматически, надо проверить.", "Субтитры создали автоматически, надо проверить."),
        ("Нам нужен корректор. Потом опубликуем.", "Нам нужен корректор. Потом опубликуем."),
        ("The audio is transcribed by Whisper locally.", "The audio is transcribed by Whisper locally."),
        ("50 € это будет стоить. Субтитры делал DimaTorzok", "50 € это будет стоить."),
        ("Отправь отчёт. Редактор субтитров А.Семкин Корректор А.Егорова", "Отправь отчёт."),
        ("Спасибо. Субтитры сделаны сообществом Amara.org", "Спасибо."),
        ("Субтитры подготовил Игорь Негода", ""),
        ("умножь 2*3*4", "умножь 2*3*4"),
        ("массив [1, 2, 3] пустой", "массив [1, 2, 3] пустой"),
        ("Сделай это (если сможешь)", "Сделай это (если сможешь)"),
        ("Привет (музыка)", "Привет"),
        ("*Police* Hello", "Hello"),
        ("–5 градусов", "–5 градусов"),
        ("- 5 градусов", "- 5 градусов"),
        ("— и тогда мы пошли", "и тогда мы пошли"),
    ])
    func artifacts(input: String, expected: String) {
        #expect(TextCleanup.removeWhisperArtifacts(input) == expected)
    }

    @Test(arguments: [
        ("The trial period ends tomorrow", "The trial period ends tomorrow"),
        ("Это стартовая точка проекта", "Это стартовая точка проекта"),
        ("a new line of products", "a new line of products"),
        ("привет точка как дела", "привет. Как дела"),
        ("done period next thing", "done. Next thing"),
        ("запятая стоит тут", "запятая стоит тут"),
    ])
    func spokenPunctuation(input: String, expected: String) {
        #expect(TextCleanup.applySpokenPunctuation(input) == expected)
    }

    @Test func numbersAreNotCollapsed() {
        #expect(TextCleanup.collapseRepeats("пять пять пять") == "пять пять пять")
        #expect(TextCleanup.collapseRepeats("код один один два") == "код один один два")
        #expect(TextCleanup.collapseRepeats("I know that that works") == "I know that that works")
        #expect(TextCleanup.collapseRepeats("мы мы пойдём") == "мы пойдём")
    }

    @Test func vocabularySymbolsAndOrder() {
        #expect(Vocabulary.apply("I write C++ daily", terms: ["C++"]) == "I write C++ daily")
        #expect(Vocabulary.apply("plan c is fine", terms: ["C++"]) == "plan c is fine")
        #expect(Vocabulary.apply("c# and C#", terms: ["C#"]) == "C# and C#")
        #expect(Vocabulary.apply("net income on .net", terms: [".NET"]) == "net income on .NET")
        #expect(Vocabulary.apply("node.js and js", terms: ["Node.js", "JS"]) == "Node.js and JS")
        #expect(Vocabulary.apply("Please open. AI is great", terms: ["OpenAI"]) == "Please open. AI is great")
        #expect(Vocabulary.apply("open ai and Node. js", terms: ["OpenAI", "Node.js"]) == "OpenAI and Node.js")
    }

    @Test func vocabularyKeepsSentenceCapital() {
        let terms = ["git", "запушить", "OpenAI"]
        #expect(Vocabulary.apply("Git нужно обновить. Запушить в main", terms: terms) == "Git нужно обновить. Запушить в main")
        #expect(Vocabulary.apply("потом GIT и запушить", terms: terms) == "потом Git и запушить")
        #expect(Vocabulary.apply("Openai", terms: terms) == "OpenAI")
    }

    @Test func promptEcho() {
        let terms = ["OpenAI", "ChatGPT", "Node.js"]
        #expect(Vocabulary.isEchoOfPrompt("Термины: OpenAI, ChatGPT, Node.js.", terms: terms))
        #expect(Vocabulary.isEchoOfPrompt("OpenAI, ChatGPT.", terms: terms))
        #expect(!Vocabulary.isEchoOfPrompt("ChatGPT, OpenAI!", terms: terms))
        #expect(!Vocabulary.isEchoOfPrompt("Go, go, go!", terms: ["Go", "Rust"]))
        #expect(!Vocabulary.isEchoOfPrompt("ChatGPT", terms: terms))
        #expect(!Vocabulary.isEchoOfPrompt("Я пользуюсь OpenAI и ChatGPT", terms: terms))
    }

    @Test func codeFenceOnlyWhenWholeReply() {
        #expect(AIRewriter.sanitize("```\nHello\n```") == "Hello")
        #expect(AIRewriter.sanitize("```bash\nls\n```\n\nMore") == "```bash\nls\n```\n\nMore")
    }

    @Test func quotaVersusRateLimit() {
        #expect(OpenAIError.isQuota(Data(#"{"error":{"code":"insufficient_quota","type":"insufficient_quota"}}"#.utf8)))
        #expect(!OpenAIError.isQuota(Data(#"{"error":{"code":"rate_limit_exceeded","type":"requests"}}"#.utf8)))
    }

    @Test func rejectsModelThatIsNotAModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canto-model-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("page.bin")
        try Data("<html>error</html>".utf8).write(to: page)
        #expect(throws: (any Error).self) { try ModelDownloader.validateModel(at: page, expectedBytes: 1_000) }
        let model = directory.appendingPathComponent("model.bin")
        try (Data("lmgg".utf8) + Data(count: 996)).write(to: model)
        #expect(throws: Never.self) { try ModelDownloader.validateModel(at: model, expectedBytes: 1_000) }
    }
}
