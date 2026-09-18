import Foundation
import Testing
@testable import CantoCore

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
        #expect(store.list().map(\.name) == ["Clean up", "Markdown", "Organize", "Software Engineer", "Translate to English"])
        let engineer = try #require(store.instructions(for: "Software Engineer.md"))
        #expect(!engineer.hasPrefix("#"))
        #expect(engineer.contains("«пуш» → push"))
        #expect(store.instructions(for: "Organize.md")?.contains("no Markdown symbols") == true)
        #expect(store.instructions(for: "Clean up.md")?.contains("Never translate") == true)
    }

    @Test func leavesAnExistingFolderAlone() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try store.ensureDirectory()
        #expect(store.list().isEmpty)
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
