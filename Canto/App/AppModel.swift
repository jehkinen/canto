import AppKit
import LocalParakeet
import LocalWhisper
import Observation
import OSLog
import CantoCore
import SileroVAD

enum DictationPhase: Equatable {
    case idle
    case listening(since: Date)
    case transcribing
    case inserted
    case failed(String)
}

/// A short message shown in the HUD and the menu bar panel.
struct Notice: Equatable, Identifiable {
    enum Action: Equatable {
        case openMicrophoneSettings, grantAccessibility, openModels, openAPIKey
    }

    let id = UUID()
    var message: String
    var action: Action?
}

/// Application state and the dictation loop:
/// hotkey → microphone → voice activity detection → Whisper → text pipeline → insertion.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: State observed by the UI

    var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    private(set) var phase: DictationPhase = .idle {
        didSet {
            if phase == .transcribing {
                if transcribingSince == nil { transcribingSince = Date() }
            } else {
                transcribingSince = nil
            }
        }
    }
    /// When the current wait for recognition began, for the elapsed time in the UI.
    private(set) var transcribingSince: Date?
    private(set) var level: Float = 0
    /// Listening has started but the microphone has not delivered sound yet (Bluetooth warm-up).
    private(set) var microphoneWarmingUp = false
    private(set) var notice: Notice?
    private(set) var history: [TranscriptEntry]
    private(set) var devices: [AudioInputDevice] = []
    private(set) var defaultDeviceName: String?
    private(set) var microphoneAccess = Permissions.microphone
    private(set) var accessibilityGranted = Permissions.accessibility
    private(set) var models: [WhisperModelInfo] = []
    private(set) var downloads: [WhisperModelKind: DownloadProgress] = [:]
    private(set) var hasAPIKey = KeychainStore.hasAPIKey()
    private(set) var keychainMatches: [KeychainStore.FoundItem] = []
    private(set) var keychainSearchMessage: String?
    var isChoosingKeychainItem = false
    private(set) var skills: [Skill] = []
    private(set) var hotkeyConflict = false
    private(set) var isMicrophoneTestRunning = false
    var isRecordingShortcut = false {
        didSet { registerHotkey() }
    }

    var isListening: Bool {
        if case .listening = phase { true } else { false }
    }

    var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: Keys.onboardingCompleted)
    }

    /// Setup problems that stop dictation from working, most important first.
    var setupIssues: [Notice] {
        var issues: [Notice] = []
        if microphoneAccess != .granted {
            issues.append(Notice(message: String(localized: "Allow microphone access"), action: .openMicrophoneSettings))
        }
        if !accessibilityGranted {
            issues.append(Notice(message: String(localized: "Allow Accessibility to insert text"), action: .grantAccessibility))
        }
        if settings.transcriptionProvider == .local, activeWhisperModel(for: settings) == nil {
            issues.append(Notice(message: String(localized: "Download a speech model"), action: .openModels))
        }
        if settings.needsAPIKey, !hasAPIKey {
            issues.append(Notice(message: String(localized: "Add your OpenAI API key"), action: .openAPIKey))
        }
        return issues
    }

    var modelStore: WhisperModelStore {
        WhisperModelStore(directory: AppPaths.modelsDirectory(for: settings))
    }

    // MARK: Private

    private enum Keys {
        static let settings = "settings"
        static let onboardingCompleted = "onboardingCompleted"
    }

    private let logger = Logger(subsystem: "io.github.jehkinen.canto", category: "dictation")
    private let hotkeys = HotkeyCenter()
    private let recorder = AudioRecorder()
    private let historyStore = TranscriptHistory(fileURL: AppPaths.historyFile)
    private var detector: VoiceActivityDetector?
    private var insertionChain: Task<Void, Never>?
    private var recognitionTasks: [Task<Recognition?, Never>] = []
    private var jobGeneration = 0
    private(set) var jobsInFlight = 0
    private var whisper: WhisperTranscriber?
    private var parakeet: ParakeetTranscriber?
    private var unloadTask: Task<Void, Never>?
    private var cachedAPIKey: String?
    private var downloadTasks: [WhisperModelKind: Task<Void, Never>] = [:]
    private var noticeTask: Task<Void, Never>?
    private var phaseResetTask: Task<Void, Never>?
    private var permissionPoll: Timer?
    private var microphoneRestarts = 0
    private var microphoneStartedAt = Date()
    private var warmUpTask: Task<Void, Never>?
    /// Identifies a listening session, so a microphone start that finishes late only
    /// affects the session that asked for it.
    private var listeningSession = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.settings),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved.sanitized()
        } else {
            settings = AppSettings()
        }
        history = TranscriptHistory(fileURL: AppPaths.historyFile).load()
    }

    // MARK: Lifecycle

    func start() {
        hotkeys.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkeys.onRelease = { [weak self] in self?.hotkeyReleased() }
        registerHotkey()
        if settings.capsLockAsHotkey {
            applyCapsLockRemap(true)
        }

        recorder.onLevel = { [weak self] level in self?.level = level }
        recorder.onLive = { [weak self] in self?.microphoneBecameLive() }
        recorder.onInterruption = { [weak self] in self?.microphoneInterrupted() }

        refreshDevices()
        AudioDevices.observeChanges { [weak self] in self?.refreshDevices() }
        refreshModels()
        refreshSkills()
        SileroVoiceClassifier.prepare()
        prewarmLocalModel()

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.refreshPermissions() }
        }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.refreshPermissions() }
        }
    }

    func prepareForQuit() {
        recorder.stop()
        CapsLockRemapper.restoreOnQuit()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Keys.onboardingCompleted)
    }

    // MARK: Dictation

    private func hotkeyPressed() {
        guard settings.isEnabled, !isRecordingShortcut else { return }
        switch settings.activationMode {
        case .pushToTalk:
            startListening()
        case .toggle:
            isListening ? stopListening() : startListening()
        }
    }

    private func hotkeyReleased() {
        guard settings.activationMode == .pushToTalk, isListening else { return }
        stopListening()
    }

    func toggleListeningFromUI() {
        isListening ? stopListening() : startListening()
    }

    private func startListening() {
        guard !isListening else { return }
        guard preflight() else {
            if settings.playSounds { SoundEffects.failure() }
            return
        }
        stopMicrophoneTest()

        let detector = VoiceActivityDetector(configuration: settings.vadConfiguration, classifier: voiceClassifier())
        detector.endsOnSilence = settings.activationMode == .toggle
        detector.recordsEverything = settings.activationMode == .pushToTalk
        self.detector = detector
        microphoneRestarts = 0
        recorder.setSampleHandler { [weak self] samples in
            for case .speechEnded(let segment) in detector.push(samples) {
                DispatchQueue.main.async { self?.enqueue(segment) }
            }
        }

        microphoneStartedAt = Date()
        // A model unloaded after idle loads again while the user speaks.
        unloadTask?.cancel()
        prewarmLocalModel()
        phaseResetTask?.cancel()
        phase = .listening(since: Date())
        // The start sound means "speak now", so it waits until the microphone delivers sound.
        microphoneWarmingUp = true
        warmUpTask?.cancel()
        listeningSession += 1
        let session = listeningSession
        Task {
            do {
                try await recorder.start(deviceUID: settings.microphoneUID)
            } catch {
                microphoneStartFailed(error, session: session)
                return
            }
            guard session == listeningSession, isListening, microphoneWarmingUp else { return }
            warmUpTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                self?.microphoneBecameLive()
            }
        }
    }

    /// Silero once its model has loaded; libfvad until then or if it can not load, so a recording
    /// never waits for the model.
    private func voiceClassifier() -> any VoiceClassifier {
        if let silero = SileroVoiceClassifier.make() { return silero }
        logger.notice("Silero VAD is not loaded, this recording uses libfvad")
        return WebRTCVoiceClassifier()
    }

    private func microphoneStartFailed(_ error: Error, session: Int) {
        logger.error("microphone start failed: \(String(describing: error), privacy: .public)")
        guard session == listeningSession else { return }
        let message = (error as? AudioRecorderError) == .timedOut
            ? String(localized: "The microphone did not respond. Try again or choose another one")
            : String(localized: "The microphone could not be started")
        if isListening {
            // Nothing was recorded, so the session ends quietly.
            microphoneWarmingUp = false
            warmUpTask?.cancel()
            detector = nil
            recorder.stop()
            phase = jobsInFlight > 0 ? .transcribing : .idle
        }
        fail(message)
    }

    private func microphoneBecameLive() {
        guard isListening, microphoneWarmingUp else { return }
        microphoneWarmingUp = false
        warmUpTask?.cancel()
        let delay = Date().timeIntervalSince(microphoneStartedAt)
        logger.info("microphone live after \(delay, format: .fixed(precision: 2), privacy: .public)s")
        phase = .listening(since: Date())
        if settings.playSounds { SoundEffects.start() }
    }

    private func stopListening() {
        guard isListening, let detector else { return }
        microphoneWarmingUp = false
        warmUpTask?.cancel()
        self.detector = nil
        let pushToTalk = settings.activationMode == .pushToTalk
        // Runs after every chunk the tap already queued, so nothing recorded is lost.
        recorder.stop { [weak self] in
            let segment = pushToTalk ? detector.flushPushToTalk() : detector.flush()
            DispatchQueue.main.async {
                guard let self else { return }
                if let segment { self.enqueue(segment) }
                self.updatePhaseAfterWork()
            }
        }
        phase = jobsInFlight > 0 ? .transcribing : .idle
        if settings.playSounds { SoundEffects.stop() }
    }

    /// The input device changed under a running engine, for example a Bluetooth headset
    /// switching to its microphone profile. Restart capture and keep the phrase in progress.
    private func microphoneInterrupted() {
        guard isListening || isMicrophoneTestRunning else { return }
        microphoneRestarts += 1
        guard microphoneRestarts <= 3 else {
            microphoneLost()
            return
        }
        let session = listeningSession
        Task {
            do {
                try await recorder.start(deviceUID: settings.microphoneUID)
            } catch {
                logger.error("microphone restart failed: \(String(describing: error), privacy: .public)")
                if session == listeningSession { microphoneLost() }
            }
        }
    }

    private func microphoneLost() {
        if isMicrophoneTestRunning {
            isMicrophoneTestRunning = false
            recorder.stop()
        } else if isListening {
            stopListening()
        } else {
            return
        }
        show(Notice(message: String(localized: "The microphone changed, listening stopped")))
    }

    /// Checks everything a dictation needs and explains what is missing.
    private func preflight() -> Bool {
        refreshPermissions()
        switch microphoneAccess {
        case .granted:
            break
        case .notDetermined:
            Task {
                _ = await Permissions.requestMicrophone()
                refreshPermissions()
            }
            return false
        case .denied:
            fail(String(localized: "Allow microphone access"), action: .openMicrophoneSettings)
            return false
        }
        if settings.transcriptionProvider == .local, activeWhisperModel(for: settings) == nil {
            fail(String(localized: "Download a speech model"), action: .openModels)
            return false
        }
        if settings.transcriptionProvider == .openAI, apiKey() == nil {
            fail(String(localized: "Add your OpenAI API key"), action: .openAPIKey)
            return false
        }
        return true
    }

    /// A phrase once recognized and processed, waiting for its turn to be inserted.
    private struct Recognition {
        var text: String
        var pressEnter: Bool
        var rewriteFallback: Bool
        var usedLocalFallback: Bool
        var provider: TranscriptionProvider
        var recognitionTime: TimeInterval
        var processingTime: TimeInterval
        var skillName: String?
        var recognized: String
    }

    /// Phrases are recognized as soon as they end, in parallel, so one slow request does not hold
    /// up the next ones; they are still inserted strictly in the order they were spoken.
    private func enqueue(_ segment: AudioSegment) {
        jobsInFlight += 1
        if !isListening { phase = .transcribing }
        let endedAt = Date()
        let generation = jobGeneration
        let settings = self.settings
        let recognition = Task { await self.recognize(segment, settings: settings) }
        recognitionTasks.append(recognition)
        let previous = insertionChain
        insertionChain = Task { [weak self] in
            await previous?.value
            let result = await recognition.value
            guard let self, generation == self.jobGeneration else { return }
            if let result {
                await self.deliver(result, segment: segment, endedAt: endedAt, settings: settings)
            }
            self.recognitionTasks.removeAll { $0 == recognition }
            self.jobsInFlight -= 1
            self.updatePhaseAfterWork()
        }
    }

    /// Stops waiting for phrases that are still being recognized; nothing more gets inserted.
    func cancelTranscription() {
        guard jobsInFlight > 0 else { return }
        jobGeneration += 1
        recognitionTasks.forEach { $0.cancel() }
        recognitionTasks.removeAll()
        insertionChain = nil
        jobsInFlight = 0
        if !isListening { phase = .idle }
    }

    private func updatePhaseAfterWork() {
        guard !isListening, jobsInFlight == 0 else { return }
        if phase == .transcribing { phase = .idle }
        scheduleModelUnload()
    }

    /// Frees the local model's memory after the configured idle time; the next key press loads it again.
    private func scheduleModelUnload() {
        unloadTask?.cancel()
        let minutes = settings.unloadModelAfterMinutes
        guard minutes > 0, whisper != nil || parakeet != nil else { return }
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self, !self.isListening, self.jobsInFlight == 0 else { return }
            self.whisper = nil
            self.parakeet = nil
            self.logger.info("model unloaded after \(minutes, privacy: .public) min idle")
        }
    }

    private func recognize(_ segment: AudioSegment, settings: AppSettings) async -> Recognition? {
        let prepared = AudioPreprocessor.process(segment, enabled: settings.audioPreprocessing)
        // Under 0.6 s there is hardly any speech, but Whisper still answers with subtitle filler.
        guard !prepared.skippedAsSilence, prepared.segment.duration >= 0.6 else { return nil }
        let prompt = Vocabulary.prompt(for: settings.vocabulary, language: settings.language)

        var raw: String
        var provider = settings.transcriptionProvider
        var usedLocalFallback = false
        let recognitionStart = Date()
        do {
            raw = try await transcriber(for: settings).transcribe(prepared.segment, language: settings.language, prompt: prompt)
        } catch {
            guard !Task.isCancelled else { return nil }
            logger.error("transcription failed: \(String(describing: error), privacy: .public)")
            // No answer from OpenAI: a downloaded model on this Mac can still do the job.
            guard settings.transcriptionProvider == .openAI, Self.isConnectionProblem(error),
                  let local = localFallbackTranscriber(for: settings) else {
                fail(Self.message(for: error))
                return nil
            }
            do {
                raw = try await local.transcribe(prepared.segment, language: settings.language, prompt: prompt)
                provider = .local
                usedLocalFallback = true
            } catch {
                guard !Task.isCancelled else { return nil }
                fail(Self.message(for: error))
                return nil
            }
        }
        let recognitionTime = Date().timeIntervalSince(recognitionStart)
        guard !Task.isCancelled, !Vocabulary.isEchoOfPrompt(raw, terms: settings.vocabulary) else { return nil }

        let processingStart = Date()
        let processed = await process(raw, settings: settings)
        guard !Task.isCancelled else { return nil }
        let skillName = processed.skills.isEmpty ? nil : processed.skills.joined(separator: " + ")
        return Recognition(text: processed.text, pressEnter: processed.pressEnter, rewriteFallback: processed.rewriteFallback,
                           usedLocalFallback: usedLocalFallback, provider: provider, recognitionTime: recognitionTime,
                           processingTime: Date().timeIntervalSince(processingStart), skillName: skillName,
                           recognized: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Recognized text through cleanup, numbers, vocabulary and the chosen skill.
    private func process(_ raw: String, settings: AppSettings) async -> ProcessedText {
        // A local model can take a while to load on its first request.
        let session = OpenAISession.make(totalTimeout: 120)
        defer { session.finishTasksAndInvalidate() }
        return await TextPipeline(chat: skillChat(for: settings, session: session), skills: SkillStore(directory: AppPaths.skillsDirectory),
                                  model: Self.skillModel(for: settings))
            .process(raw, settings: settings, fallbackLanguage: Self.interfaceLanguage)
    }

    struct ProcessingTrial: Equatable {
        var text: String
        var seconds: TimeInterval
        var problem: String?
    }

    /// Runs typed text through the same processing as a dictated phrase, to try a skill.
    func tryProcessing(_ text: String) async -> ProcessingTrial {
        let start = Date()
        let processed = await process(text, settings: settings)
        let problem = processed.rewriteFallbackReason.map { String(localized: "The skill did not run: \($0)") }
        return ProcessingTrial(text: processed.text, seconds: Date().timeIntervalSince(start), problem: problem)
    }

    private func deliver(_ result: Recognition, segment: AudioSegment, endedAt: Date, settings: AppSettings) async {
        // Text without letters or digits ("---", "…") is an artifact of a noise-only phrase.
        let hasContent = result.text.contains { $0.isLetter || $0.isNumber }
        guard hasContent || result.pressEnter else { return }

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let outcome = await TextInserter.insert(hasContent ? result.text : "", method: settings.insertionMethod,
                                                pressReturn: result.pressEnter && settings.pressEnterOnTrigger)
        let latency = Date().timeIntervalSince(endedAt)
        logger.info("""
            phrase \(segment.duration, format: .fixed(precision: 1), privacy: .public)s via \(result.provider.rawValue, privacy: .public)\
            \(result.usedLocalFallback ? " (OpenAI fallback)" : "", privacy: .public): \
            recognition \(result.recognitionTime, format: .fixed(precision: 2), privacy: .public)s, \
            \(settings.textProcessingMode.rawValue, privacy: .public)\(result.skillName.map { " + " + $0 } ?? "", privacy: .public) \
            \(result.processingTime, format: .fixed(precision: 2), privacy: .public)s, \
            total \(latency, format: .fixed(precision: 2), privacy: .public)s, inserted \(result.text.count, privacy: .public) chars \
            into \(appName ?? "?", privacy: .public) (\(String(describing: outcome), privacy: .public))
            """)
        if settings.keepHistory, hasContent {
            addToHistory(TranscriptEntry(text: result.text, duration: segment.duration, provider: result.provider,
                                         processingMode: settings.textProcessingMode, appName: appName, latency: latency,
                                         skill: result.skillName,
                                         recognized: result.recognized == result.text ? nil : result.recognized))
        }

        switch outcome {
        case .copiedToPasteboard:
            show(Notice(message: String(localized: "Copied. Allow Accessibility to paste automatically"), action: .grantAccessibility))
        case .inserted where result.usedLocalFallback:
            show(Notice(message: String(localized: "OpenAI did not respond, recognized on this Mac")))
        case .inserted where result.rewriteFallback:
            show(Notice(message: String(localized: "The skill did not run, inserted the text without it"),
                        action: settings.aiProvider == .openAI ? .openAPIKey : nil))
        case .inserted:
            if !isListening, jobsInFlight <= 1 {
                phase = .inserted
                schedulePhaseReset(after: .milliseconds(900))
            }
        }
    }

    static func isConnectionProblem(_ error: Error) -> Bool {
        switch error as? TranscriptionError {
        case .network, .server: true
        default: false
        }
    }

    private func localFallbackTranscriber(for settings: AppSettings) -> (any Transcriber)? {
        let store = modelStore
        guard let kind = ([settings.whisperModel] + WhisperModelKind.available).first(where: { store.isInstalled($0) }) else {
            return nil
        }
        var local = settings
        local.transcriptionProvider = .local
        local.whisperModel = kind
        return try? transcriber(for: local)
    }

    private func transcriber(for settings: AppSettings) throws -> any Transcriber {
        switch settings.transcriptionProvider {
        case .openAI:
            guard let key = apiKey() else { throw TranscriptionError.apiKeyMissing }
            return OpenAITranscriber(apiKey: key, model: settings.openAITranscriptionModel)
        case .local:
            // While the chosen model is still downloading, another downloaded one does the work.
            let model = activeWhisperModel(for: settings) ?? settings.whisperModel
            let store = WhisperModelStore(directory: AppPaths.modelsDirectory(for: settings))
            if model.engine == .parakeet {
                if let parakeet, parakeet.directory == store.url(for: model) { return parakeet }
                let fresh = ParakeetTranscriber(directory: store.url(for: model))
                parakeet = fresh
                return fresh
            }
            let configuration = WhisperTranscriber.Configuration(
                modelURL: store.url(for: model),
                useGPU: settings.whisperUseGPU,
                beamSize: settings.whisperBeamSize
            )
            if let whisper, whisper.configuration == configuration { return whisper }
            let fresh = WhisperTranscriber(configuration: configuration)
            whisper = fresh
            return fresh
        }
    }

    /// The model local recognition uses: the chosen one once it is downloaded, otherwise the first
    /// downloaded model, so dictation keeps working during a download.
    func activeWhisperModel(for settings: AppSettings) -> WhisperModelKind? {
        let store = WhisperModelStore(directory: AppPaths.modelsDirectory(for: settings))
        if store.isInstalled(settings.whisperModel) { return settings.whisperModel }
        return WhisperModelKind.available.first { store.isInstalled($0) }
    }

    private func prewarmLocalModel() {
        if settings.transcriptionProvider == .openAI {
            // Loading the AAC codec takes over a second the first time; do it before the first phrase.
            Task.detached(priority: .utility) {
                _ = CompressedAudioEncoder.m4a(AudioSegment(samples: [Float](repeating: 0, count: 1_600)))
            }
            return
        }
        guard settings.transcriptionProvider == .local, activeWhisperModel(for: settings) != nil,
              let local = try? transcriber(for: settings) else { return }
        let logger = self.logger
        Task.detached(priority: .userInitiated) {
            let start = Date()
            if let whisper = local as? WhisperTranscriber { try? await whisper.prepare() }
            if let parakeet = local as? ParakeetTranscriber { try? await parakeet.prepare() }
            let seconds = Date().timeIntervalSince(start)
            // Already loaded models return at once; only real loads are worth a line.
            if seconds > 0.05 {
                logger.info("model ready in \(seconds, format: .fixed(precision: 2), privacy: .public)s")
            }
            await MainActor.run { AppModel.shared.scheduleModelUnload() }
        }
    }

    private func fail(_ message: String, action: Notice.Action? = nil) {
        show(Notice(message: message, action: action))
        // A phrase can fail while the next one is being recorded: the microphone is still on,
        // and the phase has to keep saying so, or releasing the key would not stop it.
        guard !isListening else { return }
        phase = .failed(message)
        schedulePhaseReset(after: .seconds(3))
    }

    private func schedulePhaseReset(after delay: Duration) {
        phaseResetTask?.cancel()
        phaseResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isListening else { return }
            self.phase = self.jobsInFlight > 0 ? .transcribing : .idle
        }
    }

    func show(_ notice: Notice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    #if SNAPSHOTS
    func setSnapshotDownload(_ kind: WhisperModelKind, progress: DownloadProgress) {
        downloads[kind] = progress
    }

    func setSnapshotState(phase: DictationPhase, level: Float, history: [TranscriptEntry]? = nil) {
        self.phase = phase
        self.level = level
        if let history { self.history = history }
        // Screenshots show a set-up app.
        microphoneAccess = .granted
        accessibilityGranted = true
        devices = [AudioInputDevice(id: 1, uid: "built-in", name: "MacBook Pro Microphone")]
    }
    #endif

    func dismissNotice() {
        notice = nil
    }

    static func message(for error: Error) -> String {
        switch error as? TranscriptionError {
        case .apiKeyMissing: String(localized: "Add your OpenAI API key")
        case .modelNotFound: String(localized: "Download a speech model")
        case .modelLoadFailed: String(localized: "The speech model could not be loaded")
        case .authentication: String(localized: "OpenAI rejected the API key")
        case .quotaExceeded: String(localized: "OpenAI quota exceeded")
        case .network: String(localized: "No connection to OpenAI")
        case .server, .inferenceFailed, .cancelled, nil: String(localized: "Transcription failed")
        }
    }

    /// The language Canto's interface runs in, used when Whisper detects the language itself.
    static var interfaceLanguage: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("ru") == true ? "ru" : "en"
    }

    // MARK: Settings

    private func settingsDidChange(from old: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Keys.settings)
        }
        if settings.hotkey != old.hotkey || settings.isEnabled != old.isEnabled {
            registerHotkey()
        }
        if settings.capsLockAsHotkey != old.capsLockAsHotkey {
            applyCapsLockRemap(settings.capsLockAsHotkey)
        }
        if settings.activationMode != old.activationMode, isListening {
            stopListening()
        }
        if settings.whisperModelsDirectory != old.whisperModelsDirectory {
            refreshModels()
        }
        if settings.unloadModelAfterMinutes != old.unloadModelAfterMinutes {
            scheduleModelUnload()
        }
        if settings.transcriptionProvider != old.transcriptionProvider || settings.whisperModel != old.whisperModel
            || settings.whisperUseGPU != old.whisperUseGPU || settings.whisperModelsDirectory != old.whisperModelsDirectory {
            whisper = nil
            parakeet = nil
            prewarmLocalModel()
        }
        if !settings.keepHistory, old.keepHistory {
            clearHistory()
        }
    }

    private func registerHotkey() {
        guard settings.isEnabled, !isRecordingShortcut else {
            hotkeys.unregister()
            hotkeyConflict = false
            return
        }
        hotkeyConflict = !hotkeys.register(settings.hotkey)
    }

    private func applyCapsLockRemap(_ enabled: Bool) {
        do {
            try CapsLockRemapper.setEnabled(enabled)
        } catch {
            logger.error("hidutil failed: \(error.localizedDescription, privacy: .public)")
            show(Notice(message: String(localized: "Caps Lock could not be remapped")))
        }
    }

    func resetSettings() {
        let keepCapsLock = settings.capsLockAsHotkey
        settings = AppSettings()
        if keepCapsLock { applyCapsLockRemap(false) }
    }

    // MARK: Devices and permissions

    func refreshDevices() {
        devices = AudioDevices.inputDevices()
        defaultDeviceName = AudioDevices.defaultInputDevice()?.name
    }

    func refreshPermissions() {
        let microphone = Permissions.microphone
        if microphone != microphoneAccess { microphoneAccess = microphone }
        let accessibility = Permissions.accessibility
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
    }

    func requestMicrophone() {
        if microphoneAccess == .notDetermined {
            Task {
                _ = await Permissions.requestMicrophone()
                refreshPermissions()
            }
        } else {
            Permissions.openMicrophoneSettings()
        }
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    func startMicrophoneTest() {
        guard !isListening, !isMicrophoneTestRunning, microphoneAccess == .granted else {
            if microphoneAccess != .granted { requestMicrophone() }
            return
        }
        recorder.setSampleHandler(nil)
        microphoneRestarts = 0
        isMicrophoneTestRunning = true
        listeningSession += 1
        let session = listeningSession
        Task {
            do {
                try await recorder.start(deviceUID: settings.microphoneUID)
            } catch {
                logger.error("microphone test failed: \(String(describing: error), privacy: .public)")
                guard session == listeningSession, isMicrophoneTestRunning else { return }
                isMicrophoneTestRunning = false
                recorder.stop()
                show(Notice(message: String(localized: "The microphone could not be started")))
            }
        }
    }

    func stopMicrophoneTest() {
        guard isMicrophoneTestRunning else { return }
        recorder.stop()
        isMicrophoneTestRunning = false
    }

    // MARK: Models

    func refreshModels() {
        models = modelStore.models()
    }

    func download(_ kind: WhisperModelKind) {
        guard downloadTasks[kind] == nil else { return }
        let total = Int64(kind.approximateSizeMB) * 1_000_000
        downloads[kind] = DownloadProgress(receivedBytes: 0, totalBytes: total)
        let store = modelStore
        let report: @Sendable (DownloadProgress) -> Void = { progress in
            Task { @MainActor in
                if AppModel.shared.downloads[kind] != nil { AppModel.shared.downloads[kind] = progress }
            }
        }
        downloadTasks[kind] = Task { [weak self] in
            do {
                switch kind.engine {
                case .whisper:
                    try await store.download(kind, progress: report)
                case .parakeet:
                    // FluidAudio reports a fraction of the whole bundle; the size is its known total.
                    try await ParakeetModels.download(to: store.url(for: kind)) { fraction in
                        report(DownloadProgress(receivedBytes: Int64(Double(total) * fraction), totalBytes: total))
                    }
                    try Task.checkCancellation()
                    try store.markComplete(kind)
                }
                self?.finishDownload(kind, error: nil)
            } catch {
                self?.finishDownload(kind, error: error)
            }
        }
    }

    func cancelDownload(_ kind: WhisperModelKind) {
        downloadTasks[kind]?.cancel()
    }

    private func finishDownload(_ kind: WhisperModelKind, error: Error?) {
        downloadTasks[kind] = nil
        downloads[kind] = nil
        refreshModels()
        if let error, !(error is CancellationError), (error as? URLError)?.code != .cancelled {
            show(Notice(message: String(localized: "The model download failed")))
        } else if error == nil, settings.whisperModel == kind {
            whisper = nil
            parakeet = nil
            prewarmLocalModel()
        }
    }

    func deleteModel(_ kind: WhisperModelKind) {
        if settings.whisperModel == kind {
            whisper = nil
            parakeet = nil
        }
        try? modelStore.delete(kind)
        refreshModels()
    }

    func chooseModelsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppPaths.modelsDirectory(for: settings)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.whisperModelsDirectory = url.path
        }
    }

    // MARK: OpenAI key

    private func apiKey() -> String? {
        if let cachedAPIKey { return cachedAPIKey }
        cachedAPIKey = KeychainStore.loadAPIKey()
        return cachedAPIKey
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.saveAPIKey(trimmed)
            cachedAPIKey = trimmed
            hasAPIKey = true
        } catch {
            show(Notice(message: String(localized: "The key could not be saved to the keychain")))
        }
    }

    func removeAPIKey() {
        KeychainStore.deleteAPIKey()
        cachedAPIKey = nil
        hasAPIKey = false
    }

    /// Looks for an OpenAI key another app saved in the keychain.
    func findAPIKeyInKeychain() {
        keychainSearchMessage = nil
        let items = KeychainStore.findOpenAIKeyItems()
        switch items.count {
        case 0:
            keychainSearchMessage = String(localized: "No OpenAI keys were found in the keychain")
        case 1:
            useKeychainItem(items[0])
        default:
            keychainMatches = items
            isChoosingKeychainItem = true
        }
    }

    func useKeychainItem(_ item: KeychainStore.FoundItem) {
        isChoosingKeychainItem = false
        guard let secret = KeychainStore.readSecret(of: item)?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty else {
            keychainSearchMessage = String(localized: "The keychain item could not be read")
            return
        }
        guard secret.hasPrefix("sk-") else {
            keychainSearchMessage = String(localized: "“\(item.title)” does not look like an OpenAI key")
            return
        }
        saveAPIKey(secret)
        keychainSearchMessage = nil
    }

    // MARK: Skills

    /// The chat model a skill runs on, or `nil` without a skill or a way to reach a model.
    private func skillChat(for settings: AppSettings, session: URLSession) -> (any ChatCompleting)? {
        guard !settings.skills.isEmpty else { return nil }
        switch settings.aiProvider {
        case .openAI: return apiKey().map { OpenAIChatClient(apiKey: $0, session: session) }
        case .localServer: return OpenAIChatClient(serverURL: settings.aiServerURL, session: session)
        }
    }

    private static func skillModel(for settings: AppSettings) -> String {
        let local = settings.aiServerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings.aiProvider == .localServer && !local.isEmpty ? local : AIRewriter.model
    }

    func refreshSkills() {
        let store = SkillStore(directory: AppPaths.skillsDirectory)
        try? store.ensureDirectory()
        skills = store.list()
    }

    func openSkillsFolder() {
        try? SkillStore(directory: AppPaths.skillsDirectory).ensureDirectory()
        NSWorkspace.shared.open(AppPaths.skillsDirectory)
    }

    func importSkill() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let skill = try SkillStore(directory: AppPaths.skillsDirectory).importSkill(from: url)
            refreshSkills()
            if !settings.skills.contains(skill.fileName) { settings.skills.append(skill.fileName) }
        } catch {
            show(Notice(message: String(localized: "The skill could not be imported")))
        }
    }

    // MARK: History

    private func addToHistory(_ entry: TranscriptEntry) {
        history.insert(entry, at: 0)
        if history.count > TranscriptHistory.limit {
            history.removeLast(history.count - TranscriptHistory.limit)
        }
        saveHistory()
    }

    func deleteHistory(_ ids: Set<TranscriptEntry.ID>) {
        history.removeAll { ids.contains($0.id) }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func copy(_ entry: TranscriptEntry) {
        TextInserter.copyToPasteboard(entry.text)
    }

    private func saveHistory() {
        let entries = history
        let store = historyStore
        Task.detached(priority: .utility) {
            try? store.save(entries)
        }
    }
}
