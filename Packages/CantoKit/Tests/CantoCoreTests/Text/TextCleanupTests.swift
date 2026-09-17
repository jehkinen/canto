import Foundation
import Testing
@testable import CantoCore

struct TextCleanupTests {
    @Test(arguments: [
        ("Спасибо за просмотр!", ""),
        ("Созвон в три. Спасибо за просмотр!", "Созвон в три."),
        ("Отличная идея. Субтитры сделал DimaTorzok", "Отличная идея."),
        ("Thanks for watching.", ""),
        ("Спасибо за просмотр, но это не конец", "Спасибо за просмотр, но это не конец"),
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
        ("первая строка новая строка вторая", "первая строка\n вторая"),
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

struct StyleStoreTests {
    func makeStore() -> StyleStore {
        StyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-styles-\(UUID())"))
    }

    @Test func createsFolderWithExample() throws {
        let store = makeStore()
        try store.ensureDirectory()
        #expect(store.list() == [AIStyle(fileName: StyleStore.exampleFileName, name: "Friendly and concise")])
        #expect(store.instructions(for: StyleStore.exampleFileName)?.contains("friendly tone") == true)
    }

    @Test func importsMarkdownAndNamesItByHeading() throws {
        let store = makeStore()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("legal-\(UUID()).md")
        try "# Legal\n\nUse formal language.".write(to: source, atomically: true, encoding: .utf8)
        let style = try store.importStyle(from: source)
        #expect(style.name == "Legal")
        #expect(store.instructions(for: style.fileName) == "# Legal\n\nUse formal language.")
    }

    @Test func rejectsOtherFilesAndPathsOutsideTheFolder() throws {
        let store = makeStore()
        #expect(throws: (any Error).self) { try store.importStyle(from: URL(fileURLWithPath: "/tmp/notes.txt")) }
        #expect(store.instructions(for: "../../etc/passwd") == nil)
        #expect(store.instructions(for: nil) == nil)
    }
}
