import Foundation
import Testing
@testable import CantoCore

struct VocabularyTests {
    static let terms = ["OpenAI", "ChatGPT", "GPT", " ", "openai"]

    @Test func cleansTermList() {
        #expect(Vocabulary.terms(Self.terms) == ["OpenAI", "ChatGPT", "GPT"])
        #expect(Vocabulary.prompt(for: Self.terms) == "OpenAI, ChatGPT, GPT.")
        #expect(Vocabulary.prompt(for: ["  "]) == nil)
    }

    @Test(arguments: [
        ("я пользуюсь openai и chat gpt", "я пользуюсь OpenAI и ChatGPT"),
        ("Open AI выпустила Chat-GPT", "OpenAI выпустила ChatGPT"),
        ("модель gpt лучше", "модель GPT лучше"),
        ("openaire и chatgptish не трогаем", "openaire и chatgptish не трогаем"),
    ])
    func restoresSpelling(input: String, expected: String) {
        #expect(Vocabulary.apply(input, terms: Self.terms) == expected)
    }

    @Test(arguments: [
        ("пишем на Node. js и nextjs", "пишем на Node.js и Next.js"),
        ("бэкенд на nest js, деплой в aws и gcp", "бэкенд на NestJS, деплой в AWS и GCP"),
        ("старый проект на php и java script", "старый проект на PHP и JavaScript"),
    ])
    func restoresDeveloperTerms(input: String, expected: String) {
        #expect(Vocabulary.apply(input, terms: ["Node.js", "Next.js", "NestJS", "AWS", "GCP", "PHP", "JavaScript"]) == expected)
    }

    @Test func frameRussianPrompt() {
        #expect(Vocabulary.prompt(for: ["AWS", "GCP"], language: "ru") == "Термины: AWS, GCP.")
        #expect(Vocabulary.prompt(for: ["AWS", "GCP"], language: nil) == "AWS, GCP.")
    }


    @Test func splitsCamelCase() {
        #expect(Vocabulary.parts(of: "ChatGPT") == ["Chat", "GPT"])
        #expect(Vocabulary.parts(of: "OpenAI") == ["Open", "AI"])
        #expect(Vocabulary.parts(of: "gpt-4o") == ["gpt", "4o"])
    }

    @Test func detectsPromptEcho() {
        #expect(Vocabulary.isEchoOfPrompt("OpenAI, ChatGPT.", terms: ["OpenAI", "ChatGPT"]))
        #expect(Vocabulary.isEchoOfPrompt("Термины: OpenAI, ChatGPT.", terms: ["OpenAI", "ChatGPT"]))
        #expect(!Vocabulary.isEchoOfPrompt("OpenAI сделала ChatGPT", terms: ["OpenAI", "ChatGPT"]))
    }

    @Test func pipelineAppliesVocabularyLast() async {
        var settings = AppSettings()
        settings.textProcessingMode = .basic
        settings.vocabulary = ["ChatGPT"]
        let store = StyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-vocab-\(UUID())"))
        let processed = await TextPipeline(chat: nil, styles: store).process("chat gpt ответил", settings: settings, fallbackLanguage: "ru")
        #expect(processed.text == "ChatGPT ответил")
    }
}
