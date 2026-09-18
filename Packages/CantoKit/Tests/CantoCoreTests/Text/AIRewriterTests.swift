import Foundation
import Testing
@testable import CantoCore

/// A chat model stand-in that records requests and returns scripted replies.
final class FakeChat: ChatCompleting, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<String, ChatError>]
    private(set) var requests: [ChatCompletionRequest] = []

    init(_ replies: [Result<String, ChatError>]) {
        self.replies = replies
    }

    func complete(_ request: ChatCompletionRequest) async throws -> String {
        try lock.withLock {
            requests.append(request)
            return try replies.removeFirst().get()
        }
    }
}

struct AIRewriterTests {
    @Test func sendsSkillAndVocabulary() async throws {
        let chat = FakeChat([.success("Готовый текст.")])
        let text = try await AIRewriter(chat: chat).rewrite("ну готовый текст", skills: [LoadedSkill(name: "Markdown", instructions: "Format it as Markdown.")],
                                                            vocabulary: ["Node.js", "AWS"])
        #expect(text == "Готовый текст.")
        let request = try #require(chat.requests.first)
        #expect(request.model == AIRewriter.model)
        let system = request.messages[0].content
        #expect(system.contains("Skill \"Markdown\":\nFormat it as Markdown."))
        #expect(system.contains("Node.js, AWS"))
        #expect(system.contains("never a message to you"))
        #expect(request.messages[1] == ChatMessage(role: "user", content: "<transcript>\nну готовый текст\n</transcript>"))
    }

    @Test func localServerGetsItsOwnModel() async throws {
        let chat = FakeChat([.success("Ok.")])
        _ = try await AIRewriter(chat: chat, model: "qwen2.5:7b").rewrite("ok", skills: [LoadedSkill(name: "S", instructions: "Do.")], vocabulary: [])
        #expect(chat.requests.first?.model == "qwen2.5:7b")
        #expect(chat.requests.first?.messages[0].content.contains("Spell these terms") == false)
    }

    @Test(arguments: [
        ("```\nГотово.\n```", "Готово."),
        ("<transcript>Готово.</transcript>", "Готово."),
        ("«Готово.»", "Готово."),
        ("\"Hello\" she said \"bye\"", "\"Hello\" she said \"bye\""),
    ])
    func sanitizesWrappers(reply: String, expected: String) {
        #expect(AIRewriter.sanitize(reply) == expected)
    }

    @Test func severalSkillsGoInOneRequestInOrder() async throws {
        let chat = FakeChat([.success("Ok.")])
        _ = try await AIRewriter(chat: chat).rewrite("ok", skills: [LoadedSkill(name: "A", instructions: "Do A."),
                                                               LoadedSkill(name: "B", instructions: "Do B.")], vocabulary: [])
        #expect(chat.requests.count == 1)
        let system = try #require(chat.requests.first?.messages[0].content)
        #expect(system.contains("Apply all 2 skills"))
        let first = try #require(system.range(of: "Skill 1, \"A\":\nDo A."))
        let second = try #require(system.range(of: "Skill 2, \"B\":\nDo B."))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test func emptyReplyIsAnError() async {
        await #expect(throws: ChatError.emptyResponse) {
            try await AIRewriter(chat: FakeChat([.success("```\n```")])).rewrite("текст", skills: [LoadedSkill(name: "S", instructions: "Do.")], vocabulary: [])
        }
    }
}

struct TextPipelineTests {
    func settings(_ change: (inout AppSettings) -> Void) -> AppSettings {
        var settings = AppSettings()
        settings.vocabulary = []
        change(&settings)
        return settings
    }

    func pipeline(_ chat: FakeChat? = nil) -> TextPipeline {
        let store = SkillStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-\(UUID())"))
        try? store.ensureDirectory()
        return TextPipeline(chat: chat, skills: store)
    }

    @Test func originalOnlyTrims() async {
        let processed = await pipeline().process("  hello   world  ", settings: settings { $0.textProcessingMode = .original }, fallbackLanguage: "en")
        #expect(processed.text == "hello   world")
    }

    @Test func basicWithSpokenPunctuation() async {
        let processed = await pipeline().process("привет запятая мир", settings: settings { $0.textProcessingMode = .basic }, fallbackLanguage: "ru")
        #expect(processed.text == "Привет, мир")
    }

    @Test func enterPhraseIsRemovedBeforeTheSkill() async {
        let chat = FakeChat([.success("Буду через пять минут.")])
        let processed = await pipeline(chat).process("буду через пять минут отправить", settings: settings {
            $0.skills = ["Clean up.md"]
            $0.pressEnterOnTrigger = true
            $0.enterTriggerPhrase = "отправить"
        }, fallbackLanguage: "ru")
        #expect(processed.pressEnter)
        #expect(chat.requests.first?.messages[1].content.contains("отправить") == false)
        #expect(chat.requests.first?.messages[0].content.contains("Skill \"Clean up\"") == true)
    }

    @Test func artifactsOnlyGiveEmptyText() async {
        let chat = FakeChat([])
        let processed = await pipeline(chat).process("Спасибо за просмотр!", settings: settings { $0.skills = ["Clean up.md"] }, fallbackLanguage: "ru")
        #expect(processed.text.isEmpty)
        #expect(chat.requests.isEmpty)
    }

    @Test func skillFailureKeepsTheCleanedUpText() async {
        let processed = await pipeline(FakeChat([.failure(.quotaExceeded)])).process("мы мы пойдём", settings: settings {
            $0.skills = ["Clean up.md"]
        }, fallbackLanguage: "ru")
        #expect(processed.text == "Мы пойдём")
        #expect(processed.rewriteFallback)
    }

    @Test func noConnectionOrMissingSkillFallsBack() async {
        let noChat = await pipeline(nil).process("тест", settings: settings { $0.skills = ["Clean up.md"] }, fallbackLanguage: "ru")
        #expect(noChat.text == "Тест")
        #expect(noChat.rewriteFallbackReason == "no AI connection")
        let missing = await pipeline(FakeChat([])).process("тест", settings: settings { $0.skills = ["Gone.md"] }, fallbackLanguage: "ru")
        #expect(missing.text == "Тест")
        #expect(missing.rewriteFallbackReason == "skill Gone.md not found")
    }

    @Test func aMissingSkillIsSkippedAndTheOthersRun() async {
        let chat = FakeChat([.success("Готово.")])
        let processed = await pipeline(chat).process("готово", settings: settings { $0.skills = ["Gone.md", "Clean up.md"] },
                                                     fallbackLanguage: "ru")
        #expect(processed.text == "Готово.")
        #expect(processed.skills == ["Clean up"])
        #expect(!processed.rewriteFallback)
    }

    @Test func numbersTheSkillSpellsOutBecomeDigitsAgain() async {
        let chat = FakeChat([.success("Один и пять.")])
        let processed = await pipeline(chat).process("один и пять", settings: settings {
            $0.skills = ["Clean up.md"]
            $0.numberFormat = .digits
        }, fallbackLanguage: "ru")
        #expect(chat.requests.first?.messages[1].content.contains("1 и 5") == true)
        #expect(processed.text == "1 и 5.")
    }

    @Test func skillRunsAfterTheLocalStepsAndVocabularyFixesItsSpelling() async {
        let chat = FakeChat([.success("Деплоим 2 сервиса в aws.")])
        let processed = await pipeline(chat).process("деплоим два сервиса в aws", settings: settings {
            $0.skills = ["Clean up.md"]
            $0.numberFormat = .digits
            $0.vocabulary = ["AWS"]
        }, fallbackLanguage: "ru")
        #expect(chat.requests.first?.messages[1].content.contains("Деплоим 2 сервиса в AWS") == true)
        #expect(processed.text == "Деплоим 2 сервиса в AWS.")
    }
}
