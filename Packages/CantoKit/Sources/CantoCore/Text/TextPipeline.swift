import Foundation

public struct ProcessedText: Equatable, Sendable {
    public var text: String
    public var pressEnter: Bool
    /// The AI mode could not be used and the text was cleaned up the basic way instead.
    public var rewriteFallback: Bool
    public var rewriteFallbackReason: String?

    public init(text: String, pressEnter: Bool, rewriteFallback: Bool = false, rewriteFallbackReason: String? = nil) {
        self.text = text
        self.pressEnter = pressEnter
        self.rewriteFallback = rewriteFallback
        self.rewriteFallbackReason = rewriteFallbackReason
    }
}

/// From raw recognized text to the text that gets inserted: Whisper artifacts, spoken commands,
/// cleanup, numbers, currency and vocabulary are handled here on the Mac; a skill, when one is
/// chosen, then runs on a chat model.
public struct TextPipeline: Sendable {
    let chat: (any ChatCompleting)?
    let skills: SkillStore
    let model: String

    public init(chat: (any ChatCompleting)?, skills: SkillStore, model: String = AIRewriter.model) {
        self.chat = chat
        self.skills = skills
        self.model = model
    }

    public func process(_ raw: String, settings: AppSettings, fallbackLanguage: String) async -> ProcessedText {
        var text = TextCleanup.removeWhisperArtifacts(raw)

        // Before any rewriting, so the phrase is still recognizable.
        let enter = EnterPhrase.strip(text, phrase: settings.pressEnterOnTrigger ? settings.enterTriggerPhrase : nil)
        text = enter.text

        if settings.spokenPunctuation {
            text = TextCleanup.applySpokenPunctuation(text)
        }

        switch settings.textProcessingMode {
        case .original:
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .basic, .optimization, .structural, .mdStructural:
            text = TextCleanup.basic(text)
        }

        switch settings.numberFormat {
        case .asHeard:
            break
        case .digits:
            text = SpokenNumbers.toDigits(text)
        case .words:
            text = NumberWords.apply(text, language: settings.effectiveLanguage(fallback: fallbackLanguage))
        }
        if settings.currencySymbols {
            text = SpokenNumbers.currencySymbols(text)
        }
        if !settings.vocabulary.isEmpty {
            text = Vocabulary.apply(text, terms: settings.vocabulary)
        }

        var fallbackReason: String?
        if let fileName = settings.skill, !text.isEmpty {
            if let chat, let skill = skills.skill(named: fileName), let instructions = skills.instructions(for: fileName) {
                do {
                    text = try await AIRewriter(chat: chat, model: model)
                        .rewrite(text, skillName: skill.name, instructions: instructions, vocabulary: settings.vocabulary)
                    // The model may still bend a term's spelling.
                    if !settings.vocabulary.isEmpty {
                        text = Vocabulary.apply(text, terms: settings.vocabulary)
                    }
                } catch {
                    fallbackReason = String(describing: error)
                }
            } else {
                fallbackReason = chat == nil ? "no AI connection" : "skill \(fileName) not found"
            }
        }

        return ProcessedText(text: text, pressEnter: enter.pressEnter, rewriteFallback: fallbackReason != nil,
                             rewriteFallbackReason: fallbackReason)
    }
}
