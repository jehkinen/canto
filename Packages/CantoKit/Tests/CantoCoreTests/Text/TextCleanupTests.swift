import Foundation
import Testing
@testable import CantoCore

/// Sentences longer than a loop phrase: they loop only as whole sentences.
private let longRussian = "Мы договорились встретиться завтра утром возле входа в новый офис."
private let longEnglish = "I think we should move the meeting to next Thursday afternoon"
private let longHebrew = "אני חושב שכדאי לנו לנסות את הרעיון הזה כבר מחר בבוקר."

struct TextCleanupTests {
    @Test(arguments: [
        ("Спасибо за просмотр!", ""),
        ("Созвон в три. Спасибо за просмотр!", "Созвон в три."),
        ("Отличная идея. Субтитры сделал DimaTorzok", "Отличная идея."),
        ("Субтитры делал DimaTorzok", ""),
        ("Идея хорошая. Субтитры и перевод сделал Дима", "Идея хорошая."),
        ("Корректор: А. Егорова", ""),
        ("Готово. Subtitles by the Amara.org community", "Готово."),
        ("Включи субтитры в плеере", "Включи субтитры в плеере"),
        ("Thanks for watching.", ""),
        ("Спасибо за просмотр, но это не конец", "Спасибо за просмотр, но это не конец"),
        ("Cheers!", ""),
        ("*Police*", ""),
        ("[Music] Поехали", "Поехали"),
        ("Встретимся в пять (смех)", "Встретимся в пять"),
        ("Купи 5 (пять) яблок", "Купи 5 (пять) яблок"),
        ("— В PR-е есть конфликты", "В PR-е есть конфликты"),
        ("... и тогда поехали", "и тогда поехали"),
        ("-5 градусов на улице", "-5 градусов на улице"),
    ])
    func removesWhisperArtifacts(input: String, expected: String) {
        #expect(TextCleanup.removeWhisperArtifacts(input) == expected)
    }

    /// Phrases from the published Bag of Hallucinations (see the note in en.json) go when they end a transcript.
    @Test(arguments: [
        ("Send the report by Friday. I'm not sure if I should have used the shield.", "Send the report by Friday."),
        ("The build is green. Hello and welcome to another episode of the", "The build is green."),
        ("Let's meet at noon. Woof! Beeping.", "Let's meet at noon."),
        ("Welcome to my channel.", ""),
        ("Closed captioning provided by the Imperial News Network.", ""),
        ("Ship it on Monday. The train is now moving towards the central station.", "Ship it on Monday."),
    ])
    func removesBagOfHallucinations(input: String, expected: String) {
        #expect(TextCleanup.removeWhisperArtifacts(input) == expected)
    }

    /// Real speech with the same words stays, and so do the sentences left out of the list because people dictate them.
    @Test(arguments: [
        "Welcome to the team.",
        "The train is now moving towards the central station, so I'll be a few minutes late.",
        "Woof, what a week.",
        "I'm not sure if I should have used the shield icon here, what do you think?",
        "Can you check this config? I'm not sure what I'm doing here.",
        "I don't know.",
        "Good morning!",
        "Oops.",
        "Thank you very much.",
    ])
    func keepsDictatedSentences(input: String) {
        #expect(TextCleanup.removeWhisperArtifacts(input) == input)
    }

    @Test(arguments: [
        ("мы мы пойдём завтра", "мы пойдём завтра"),
        ("под каждую под каждую систему", "под каждую систему"),
        ("I think I think it works", "I think it works"),
        ("да да, конечно", "да да, конечно"),
        ("это очень очень важно", "это очень очень важно"),
        ("раз два три", "раз два три"),
    ])
    func collapsesRepeats(input: String, expected: String) {
        #expect(TextCleanup.collapseRepeats(input) == expected)
    }

    @Test(arguments: [
        ("Спасибо. Спасибо. Спасибо. Спасибо.", "Спасибо."),
        ("Созвон в три. Спасибо, спасибо, спасибо.", "Созвон в три. Спасибо."),
        ("и я и я и я и я пошёл домой", "и я пошёл домой"),
        ("и я — и я — и я — и я — и всё", "и я — и всё"),
        ("я думаю я думаю я я я думаю", "я думаю"),
        ("Итак,  всё   готово. Спасибо. Спасибо. Спасибо.", "Итак,  всё   готово. Спасибо."),
        ("Итак. \(longRussian) \(longRussian) \(longRussian) Дальше.", "Итак. \(longRussian) Дальше."),
        ("Thank you. Thank you. Thank you.", "Thank you."),
        ("I'm going to the I'm going to the I'm going to the store.", "I'm going to the store."),
        ("Hello, world! Hello, world! Hello, world!", "Hello, world!"),
        // Compared without case and punctuation; the last copy's punctuation stays.
        ("\(longEnglish). \(longEnglish)! \(longEnglish.lowercased())", longEnglish),
        ("תודה. תודה. תודה. תודה.", "תודה."),
        ("אני הולך הביתה אני הולך הביתה אני הולך הביתה עכשיו", "אני הולך הביתה עכשיו"),
        ("\(longHebrew) \(longHebrew) \(longHebrew)", longHebrew),
    ])
    func removesLoops(input: String, expected: String) {
        #expect(TextCleanup.removeLoops(input) == expected)
    }

    @Test(arguments: [
        // Two copies are speech; Basic mode's collapseRepeats handles a doubled stutter.
        "да да, конечно",
        "мы мы пойдём",
        "Я иду домой. Я иду домой.",
        "\(longRussian) \(longRussian)",
        // Words people repeat on purpose, however many times.
        "да да да, конечно",
        "да да да да да да",
        "это очень очень очень хорошо",
        "Давай, давай, давай!",
        "no no no, not that one",
        "Go, go, go!",
        "כן כן כן",
        "זה טוב מאוד מאוד מאוד",
        // Numbers said digit by digit.
        "пять пять пять пять",
        "код один один один два",
        "телефон 999 12 12 12",
        "12 34 12 34 12 34",
        "two two two",
        "חמש חמש חמש",
    ])
    func keepsRepeatsPeopleSay(text: String) {
        #expect(TextCleanup.removeLoops(text) == text)
    }

    @Test(arguments: [
        ("[Music] Спасибо. [Music] Спасибо. [Music] Спасибо.", "Спасибо."),
        ("— и я и я и я пошёл", "и я пошёл"),
        ("Готово. Продолжение следует... Продолжение следует... Продолжение следует...", "Готово."),
    ])
    func loopsAreWhisperArtifacts(input: String, expected: String) {
        #expect(TextCleanup.removeWhisperArtifacts(input) == expected)
    }

    @Test(arguments: [
        ("  hello   world  ", "Hello world"),
        ("привет ,как дела ?", "Привет, как дела?"),
        ("версия 3.14 в 12:30", "Версия 3.14 в 12:30"),
        ("( скобки ) и «кавычки »", "(Скобки) и «кавычки»"),
    ])
    func basicCleanup(input: String, expected: String) {
        #expect(TextCleanup.basic(input) == expected)
    }

    @Test(arguments: [
        ("привет запятая как дела вопросительный знак", "привет, как дела?"),
        ("Hello, this is the app, comma, running on my Mac.", "Hello, this is the app, running on my Mac."),
        ("Hello Comma world Period", "Hello, world."),
        ("The periodic table, question mark", "The periodic table?"),
        ("с моей точка зрения это верно точка", "с моей точка зрения это верно."),
        ("первая строка новая строка вторая", "первая строка\n Вторая"),
        ("comma at the start stays", "comma at the start stays"),
    ])
    func spokenPunctuation(input: String, expected: String) {
        #expect(TextCleanup.applySpokenPunctuation(input) == expected)
    }
}

struct NumberWordsTests {
    @Test func spellsRussianAndEnglish() {
        #expect(NumberWords.apply("у меня 42 яблока", language: "ru") == "у меня сорок два яблока")
        #expect(NumberWords.apply("I have 42 apples", language: "en") == "I have forty-two apples")
    }

    @Test func leavesVersionsTimesAndCodesAlone() {
        let text = "версия 3.14, встреча в 12:30, агент 007, модель gpt4 и v2"
        #expect(NumberWords.apply(text, language: "ru") == text)
    }
}

struct EnterPhraseTests {
    @Test func stripsPhraseAtTheEnd() {
        let result = EnterPhrase.strip("Буду через пять минут, отправить.", phrase: "отправить")
        #expect(result.text == "Буду через пять минут")
        #expect(result.pressEnter)
    }

    @Test func ignoresCaseAndSpacing() {
        #expect(EnterPhrase.strip("see you soon Send It!", phrase: " send it ") == ("see you soon", true))
    }

    @Test func needsWholeWordsAtTheEnd() {
        #expect(EnterPhrase.strip("надо переотправить", phrase: "отправить") == ("надо переотправить", false))
        #expect(EnterPhrase.strip("отправить письмо завтра", phrase: "отправить") == ("отправить письмо завтра", false))
        #expect(EnterPhrase.strip("текст", phrase: nil) == ("текст", false))
    }
}

struct SkillStoreTests {
    func makeStore() -> SkillStore {
        SkillStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-skills-\(UUID())"))
    }

    @Test func seedsTheBundledSkills() throws {
        let store = makeStore()
        try store.ensureDirectory()
        #expect(store.list().map(\.name) == ["Clean up", "Remove profanity", "Software Engineer", "Translate to English"])
        let engineer = try #require(store.instructions(for: "Software Engineer.md"))
        #expect(!engineer.hasPrefix("#"))
        #expect(engineer.contains("«пуш» → push"))
        #expect(store.instructions(for: "Clean up.md")?.contains("Never translate") == true)
    }

    @Test func fillsAnExistingFolderOnceAndKeepsTheUsersFiles() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let mine = store.directory.appendingPathComponent("Clean up.md")
        try "# Mine\n\nMy own cleanup.".write(to: mine, atomically: true, encoding: .utf8)
        try store.ensureDirectory()
        #expect(store.list().count == SkillStore.bundledSkills.count)
        #expect(store.instructions(for: "Clean up.md") == "My own cleanup.")
        // A deleted bundled skill is not offered again.
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent("Software Engineer.md"))
        try store.ensureDirectory()
        #expect(store.skill(named: "Software Engineer.md") == nil)
    }

    @Test func readsClaudeStyleFrontMatter() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appendingPathComponent("example-business-ru.md")
        try "---\nname: Business Russian\ndescription: Formal concise business tone\n---\n\nWrite in a formal tone.".write(to: file, atomically: true, encoding: .utf8)
        #expect(store.skill(named: "example-business-ru.md")?.name == "Business Russian")
        #expect(store.instructions(for: "example-business-ru.md") == "Write in a formal tone.")
    }

    @Test func importsMarkdownAndNamesItByHeading() throws {
        let store = makeStore()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("legal-\(UUID()).md")
        try "# Legal\n\nUse formal language.".write(to: source, atomically: true, encoding: .utf8)
        let skill = try store.importSkill(from: source)
        #expect(skill.name == "Legal")
        #expect(store.instructions(for: skill.fileName) == "Use formal language.")
        #expect(store.skill(named: skill.fileName) == skill)
    }

    @Test func rejectsOtherFilesAndPathsOutsideTheFolder() throws {
        let store = makeStore()
        #expect(throws: (any Error).self) { try store.importSkill(from: URL(fileURLWithPath: "/tmp/notes.txt")) }
        #expect(store.instructions(for: "../../etc/passwd") == nil)
        #expect(store.instructions(for: nil) == nil)
        #expect(store.skill(named: "Missing.md") == nil)
    }
}
