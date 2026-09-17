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
    @Test func sendsModeStyleAndVocabulary() async throws {
        let chat = FakeChat([.success("Готовый текст.")])
        let text = try await AIRewriter(chat: chat).rewrite("ну готовый текст", mode: .mdStructural,
                                                            style: "Пиши официально.", vocabulary: ["Node.js", "AWS"])
        #expect(text == "Готовый текст.")
        let request = try #require(chat.requests.first)
        #expect(request.model == AIRewriter.model)
        let system = request.messages[0].content
        #expect(system.contains("Markdown"))
        #expect(system.contains("Пиши официально."))
        #expect(system.contains("Node.js, AWS"))
        #expect(request.messages[1] == ChatMessage(role: "user", content: "<transcript>\nну готовый текст\n</transcript>"))
    }

    @Test func plainStructureForbidsMarkdown() {
        #expect(RewritePrompt.system(mode: .structural, style: nil, vocabulary: []).contains("no Markdown symbols"))
        #expect(!RewritePrompt.system(mode: .optimization, style: nil, vocabulary: []).contains("Spell these terms"))
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

    @Test func emptyReplyIsAnError() async {
        await #expect(throws: ChatError.emptyResponse) {
            try await AIRewriter(chat: FakeChat([.success("```\n```")])).rewrite("текст", mode: .optimization, style: nil, vocabulary: [])
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
        TextPipeline(chat: chat, styles: StyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-\(UUID())")))
    }

    @Test func originalOnlyTrims() async {
        let processed = await pipeline().process("  hello   world  ", settings: settings { $0.textProcessingMode = .original }, fallbackLanguage: "en")
        #expect(processed.text == "hello   world")
    }

    @Test func basicWithSpokenPunctuation() async {
        let processed = await pipeline().process("привет запятая мир", settings: settings { $0.textProcessingMode = .basic }, fallbackLanguage: "ru")
        #expect(processed.text == "Привет, мир")
    }

    @Test func enterPhraseIsRemovedBeforeRewriting() async {
        let chat = FakeChat([.success("Буду через пять минут.")])
        let processed = await pipeline(chat).process("буду через пять минут отправить", settings: settings {
            $0.textProcessingMode = .optimization
            $0.pressEnterOnTrigger = true
            $0.enterTriggerPhrase = "отправить"
        }, fallbackLanguage: "ru")
        #expect(processed.pressEnter)
        #expect(chat.requests.first?.messages[1].content.contains("отправить") == false)
    }

    @Test func artifactsOnlyGiveEmptyText() async {
        let processed = await pipeline().process("Спасибо за просмотр!", settings: settings { $0.textProcessingMode = .original }, fallbackLanguage: "ru")
        #expect(processed.text.isEmpty)
    }

    @Test func aiFailureFallsBackToBasic() async {
        let processed = await pipeline(FakeChat([.failure(.quotaExceeded)])).process("мы мы пойдём", settings: settings {
            $0.textProcessingMode = .optimization
        }, fallbackLanguage: "ru")
        #expect(processed.text == "Мы пойдём")
        #expect(processed.rewriteFallback)
    }

    @Test func missingKeyFallsBackToBasic() async {
        let processed = await pipeline(nil).process("тест", settings: settings { $0.textProcessingMode = .structural }, fallbackLanguage: "ru")
        #expect(processed.text == "Тест")
        #expect(processed.rewriteFallbackReason == "no API key")
    }

    @Test func numbersAndVocabularyRunLast() async {
        let chat = FakeChat([.success("Деплоим 2 сервиса в aws.")])
        let processed = await pipeline(chat).process("деплоим два сервиса в aws", settings: settings {
            $0.textProcessingMode = .optimization
            $0.numberFormat = .words
            $0.vocabulary = ["AWS"]
        }, fallbackLanguage: "ru")
        #expect(processed.text == "Деплоим два сервиса в AWS.")
    }
}
