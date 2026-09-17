import Foundation

/// How dictation starts and stops.
public enum ActivationMode: String, Codable, CaseIterable, Sendable {
    /// Record while the hotkey is held, transcribe on release.
    case pushToTalk
    /// The hotkey toggles listening; speech is split into phrases by voice activity detection.
    case toggle
}

public enum TranscriptionProvider: String, Codable, CaseIterable, Sendable {
    /// whisper.cpp on this Mac.
    case local
    /// OpenAI `audio/transcriptions`.
    case openAI
}

public enum TextProcessingMode: String, Codable, CaseIterable, Sendable {
    case original
    case basic
    case optimization
    case structural
    case mdStructural

    public var usesAI: Bool {
        switch self {
        case .optimization, .structural, .mdStructural: true
        case .original, .basic: false
        }
    }
}

/// How numbers appear in the finished text.
public enum NumberFormat: String, Codable, CaseIterable, Sendable {
    /// Exactly as the recognizer wrote them.
    case asHeard
    /// "двадцать пять" becomes "25".
    case digits
    /// "25" becomes "двадцать пять".
    case words
}

/// How the finished text reaches the focused app.
public enum InsertionMethod: String, Codable, CaseIterable, Sendable {
    /// Put the text on the pasteboard, press ⌘V, restore the previous pasteboard.
    case paste
    /// Type the text as synthetic Unicode key events (slower, leaves the pasteboard alone).
    case type
}

public enum WhisperModelKind: String, Codable, CaseIterable, Sendable {
    case base
    case small
    /// Large v3 Turbo, 5-bit quantized: near large-v3 accuracy at a fraction of the cost.
    case largeV3Turbo
    case medium
    case largeV3

    public var fileName: String {
        switch self {
        case .base: "ggml-base.bin"
        case .small: "ggml-small.bin"
        case .largeV3Turbo: "ggml-large-v3-turbo-q5_0.bin"
        case .medium: "ggml-medium.bin"
        case .largeV3: "ggml-large-v3.bin"
        }
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    public var approximateSizeMB: Int {
        switch self {
        case .base: 141
        case .small: 466
        case .largeV3Turbo: 574
        case .medium: 1_500
        case .largeV3: 3_100
        }
    }
}

/// A global shortcut: a virtual key code (`kVK_*`) plus Carbon-independent modifier flags.
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧F1: a function key that rarely clashes with app shortcuts.
    public static let `default` = Hotkey(keyCode: KeyCode.f1, modifiers: .shift)
    /// Caps Lock is remapped to F18 with `hidutil`, which the Carbon hotkey API can register.
    public static let capsLock = Hotkey(keyCode: KeyCode.f18)

    public enum KeyCode {
        public static let f1: UInt32 = 0x7A
        public static let f18: UInt32 = 0x4F
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var isEnabled = true
    public var activationMode: ActivationMode = .pushToTalk
    public var hotkey: Hotkey = .default
    public var capsLockAsHotkey = false
    /// The shortcut to restore when "Caps Lock as hotkey" is switched off again.
    public var hotkeyBeforeCapsLock: Hotkey?
    /// Core Audio device UID; `nil` follows the system default input.
    public var microphoneUID: String?
    /// ISO 639-1 code (`en`, `ru`); `nil` lets Whisper detect the language.
    public var language: String?

    public var transcriptionProvider: TranscriptionProvider = .local
    public var openAITranscriptionModel = "whisper-1"
    /// Names and terms to keep as written (OpenAI, ChatGPT…): they bias recognition and fix the spelling afterwards.
    public var vocabulary = ["OpenAI", "ChatGPT"]
    public var whisperModel: WhisperModelKind = .base
    /// Custom models folder; `nil` uses Application Support/Canto/Models.
    public var whisperModelsDirectory: String?
    public var whisperUseGPU = AppSettings.gpuRecommended
    public var whisperBeamSize = 1

    public var textProcessingMode: TextProcessingMode = .basic
    /// File name of the AI style (a Markdown file in the styles folder).
    public var aiStyle: String?
    public var spokenPunctuation = true
    public var numberFormat: NumberFormat = .asHeard
    /// "50 долларов" becomes "$50", "50 евро" becomes "50 €".
    public var currencySymbols = true
    public var pressEnterOnTrigger = false
    public var enterTriggerPhrase = ""

    public var audioPreprocessing = true
    public var silenceTimeoutMs = 700
    public var vadPreSpeechBufferMs = 300
    public var vadMinimumSpeechMs = 250
    public var vadMaximumSegmentMs = 30_000

    public var insertionMethod: InsertionMethod = .paste
    public var showRecordingHUD = true
    public var playSounds = true
    public var keepHistory = true

    public init() {}

    /// Metal is only worth it on Apple silicon; Intel GPUs are slower than AVX2 for Whisper.
    public static var gpuRecommended: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    /// The language used for number spelling and AI prompts when Whisper auto-detects.
    public func effectiveLanguage(fallback: String) -> String {
        language ?? fallback
    }

    public var needsAPIKey: Bool {
        transcriptionProvider == .openAI || textProcessingMode.usesAI
    }

    public var vadConfiguration: VADConfiguration {
        VADConfiguration(
            preSpeechBufferMs: vadPreSpeechBufferMs,
            minimumSpeechMs: vadMinimumSpeechMs,
            silenceTimeoutMs: silenceTimeoutMs,
            maximumSegmentMs: vadMaximumSegmentMs
        )
    }

    /// Switches the hotkey to Caps Lock (F18) and back, remembering the user's own shortcut.
    public mutating func setCapsLockAsHotkey(_ enabled: Bool) {
        guard enabled != capsLockAsHotkey else { return }
        capsLockAsHotkey = enabled
        if enabled {
            if hotkey != .capsLock {
                hotkeyBeforeCapsLock = hotkey
                hotkey = .capsLock
            }
        } else if hotkey == .capsLock {
            hotkey = hotkeyBeforeCapsLock ?? .default
            hotkeyBeforeCapsLock = nil
        } else {
            hotkeyBeforeCapsLock = nil
        }
    }

    /// Clamps values into the ranges the settings UI allows.
    public func sanitized() -> AppSettings {
        var copy = self
        copy.silenceTimeoutMs = silenceTimeoutMs.clamped(to: 200...10_000)
        copy.whisperBeamSize = whisperBeamSize.clamped(to: 1...5)
        copy.vadPreSpeechBufferMs = vadPreSpeechBufferMs.clamped(to: 50...2_000)
        copy.vadMinimumSpeechMs = vadMinimumSpeechMs.clamped(to: 50...2_000)
        copy.vadMaximumSegmentMs = vadMaximumSegmentMs.clamped(to: 1_000...120_000)
        copy.enterTriggerPhrase = String(enterTriggerPhrase.prefix(120))
        return copy
    }

    /// The synthesized keys plus the one that only older settings files have.
    enum LegacyCodingKeys: String, CodingKey {
        case numbersAsWords
    }

    // Decoding tolerates missing keys so settings saved by an older build keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        activationMode = try c.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? d.activationMode
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? d.hotkey
        capsLockAsHotkey = try c.decodeIfPresent(Bool.self, forKey: .capsLockAsHotkey) ?? d.capsLockAsHotkey
        hotkeyBeforeCapsLock = try c.decodeIfPresent(Hotkey.self, forKey: .hotkeyBeforeCapsLock)
        microphoneUID = try c.decodeIfPresent(String.self, forKey: .microphoneUID)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        transcriptionProvider = try c.decodeIfPresent(TranscriptionProvider.self, forKey: .transcriptionProvider) ?? d.transcriptionProvider
        openAITranscriptionModel = try c.decodeIfPresent(String.self, forKey: .openAITranscriptionModel) ?? d.openAITranscriptionModel
        vocabulary = try c.decodeIfPresent([String].self, forKey: .vocabulary) ?? d.vocabulary
        whisperModel = try c.decodeIfPresent(WhisperModelKind.self, forKey: .whisperModel) ?? d.whisperModel
        whisperModelsDirectory = try c.decodeIfPresent(String.self, forKey: .whisperModelsDirectory)
        whisperUseGPU = try c.decodeIfPresent(Bool.self, forKey: .whisperUseGPU) ?? d.whisperUseGPU
        whisperBeamSize = try c.decodeIfPresent(Int.self, forKey: .whisperBeamSize) ?? d.whisperBeamSize
        textProcessingMode = try c.decodeIfPresent(TextProcessingMode.self, forKey: .textProcessingMode) ?? d.textProcessingMode
        aiStyle = try c.decodeIfPresent(String.self, forKey: .aiStyle)
        spokenPunctuation = try c.decodeIfPresent(Bool.self, forKey: .spokenPunctuation) ?? d.spokenPunctuation
        // Settings saved before the three-way choice existed only had "numbers as words".
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyNumbersAsWords = try legacy.decodeIfPresent(Bool.self, forKey: .numbersAsWords) ?? false
        numberFormat = try c.decodeIfPresent(NumberFormat.self, forKey: .numberFormat) ?? (legacyNumbersAsWords ? .words : d.numberFormat)
        currencySymbols = try c.decodeIfPresent(Bool.self, forKey: .currencySymbols) ?? d.currencySymbols
        pressEnterOnTrigger = try c.decodeIfPresent(Bool.self, forKey: .pressEnterOnTrigger) ?? d.pressEnterOnTrigger
        enterTriggerPhrase = try c.decodeIfPresent(String.self, forKey: .enterTriggerPhrase) ?? d.enterTriggerPhrase
        audioPreprocessing = try c.decodeIfPresent(Bool.self, forKey: .audioPreprocessing) ?? d.audioPreprocessing
        silenceTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .silenceTimeoutMs) ?? d.silenceTimeoutMs
        vadPreSpeechBufferMs = try c.decodeIfPresent(Int.self, forKey: .vadPreSpeechBufferMs) ?? d.vadPreSpeechBufferMs
        vadMinimumSpeechMs = try c.decodeIfPresent(Int.self, forKey: .vadMinimumSpeechMs) ?? d.vadMinimumSpeechMs
        vadMaximumSegmentMs = try c.decodeIfPresent(Int.self, forKey: .vadMaximumSegmentMs) ?? d.vadMaximumSegmentMs
        insertionMethod = try c.decodeIfPresent(InsertionMethod.self, forKey: .insertionMethod) ?? d.insertionMethod
        showRecordingHUD = try c.decodeIfPresent(Bool.self, forKey: .showRecordingHUD) ?? d.showRecordingHUD
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        keepHistory = try c.decodeIfPresent(Bool.self, forKey: .keepHistory) ?? d.keepHistory
    }
}

public struct VADConfiguration: Equatable, Sendable {
    public var preSpeechBufferMs: Int
    public var minimumSpeechMs: Int
    public var silenceTimeoutMs: Int
    public var maximumSegmentMs: Int

    public init(preSpeechBufferMs: Int, minimumSpeechMs: Int, silenceTimeoutMs: Int, maximumSegmentMs: Int) {
        self.preSpeechBufferMs = preSpeechBufferMs
        self.minimumSpeechMs = minimumSpeechMs
        self.silenceTimeoutMs = silenceTimeoutMs
        self.maximumSegmentMs = maximumSegmentMs
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
