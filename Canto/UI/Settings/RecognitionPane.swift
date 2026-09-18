import SwiftUI
import CantoCore

struct RecognitionPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent {
                    Picker("Engine", selection: $model.settings.transcriptionProvider) {
                        Text("On this Mac (Whisper)").tag(TranscriptionProvider.local)
                        Text("OpenAI").tag(TranscriptionProvider.openAI)
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    HStack(spacing: 4) {
                        Text("Engine")
                        InfoButton(text: "On this Mac: speech never leaves your Mac and works without the internet. Speed and accuracy depend on the downloaded model.\n\nOpenAI: needs the internet and an API key and is paid per minute. If OpenAI does not answer, Canto uses a downloaded model on this Mac instead.")
                    }
                }
                Picker("Spoken language", selection: $model.settings.language) {
                    ForEach(Labels.languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            } footer: {
                Text(model.settings.transcriptionProvider == .local
                     ? "Speech is recognized on your Mac and never leaves it."
                     : "Audio is sent to OpenAI for recognition. Add your API key in Text & AI.")
            }

            Section {
                VocabularyEditor(terms: $model.settings.vocabulary)
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("Names and terms to write exactly like this, such as OpenAI or ChatGPT, instead of spelling them out phonetically. They guide recognition and do not slow it down.")
            }

            if model.settings.transcriptionProvider == .local {
                Section {
                    ForEach(model.models) { info in
                        ModelRow(info: info)
                    }
                } header: {
                    Text("Models")
                } footer: {
                    if let active = model.activeWhisperModel(for: model.settings), active != model.settings.whisperModel {
                        Text("Until \(Labels.model(model.settings.whisperModel)) is downloaded, \(Labels.model(active)) recognizes your speech.")
                    }
                }

                Section {
                    // GPU and decoding settings are Whisper's; Parakeet runs on the Neural Engine.
                    if model.settings.whisperModel.engine == .whisper {
                        Toggle(isOn: $model.settings.whisperUseGPU) {
                            Text("Use the GPU (Metal)")
                            Text(AppSettings.gpuRecommended
                                 ? "Much faster on Apple silicon."
                                 : "On Intel Macs the processor is usually faster.")
                        }
                        LabeledContent {
                            Picker("Decoding", selection: $model.settings.whisperBeamSize) {
                                Text("Fast").tag(1)
                                Text("Balanced").tag(3)
                                Text("Thorough").tag(5)
                            }
                            .labelsHidden()
                            .fixedSize()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Decoding")
                                InfoButton(text: "Fast takes the most likely word at each step. Balanced and Thorough compare several variants of the phrase: a little more accurate on unclear speech, but noticeably slower.")
                            }
                        }
                    }
                    LabeledContent {
                        Picker("Unload the model after", selection: $model.settings.unloadModelAfterMinutes) {
                            Text("Never").tag(0)
                            Text("1 minute").tag(1)
                            Text("5 minutes").tag(5)
                            Text("15 minutes").tag(15)
                        }
                        .labelsHidden()
                        .fixedSize()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Unload the model after")
                            InfoButton(text: "Frees memory while you are not dictating. The model loads again when you press the shortcut, usually while you are still speaking.")
                        }
                    }
                    LabeledContent("Models folder") {
                        HStack {
                            Text(AppPaths.modelsDirectory(for: model.settings).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Menu {
                                Button("Choose…") { model.chooseModelsFolder() }
                                Button("Show in Finder") {
                                    let url = AppPaths.modelsDirectory(for: model.settings)
                                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                    NSWorkspace.shared.open(url)
                                }
                                if model.settings.whisperModelsDirectory != nil {
                                    Divider()
                                    Button("Use Default Folder") { model.settings.whisperModelsDirectory = nil }
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                } header: {
                    Text("Performance")
                }
            } else {
                Section {
                    Picker("Model", selection: $model.settings.openAITranscriptionModel) {
                        Text("GPT-4o mini Transcribe").tag("gpt-4o-mini-transcribe")
                        Text("GPT-4o Transcribe").tag("gpt-4o-transcribe")
                        Text("Whisper").tag("whisper-1")
                        if !["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"].contains(model.settings.openAITranscriptionModel) {
                            Text(model.settings.openAITranscriptionModel).tag(model.settings.openAITranscriptionModel)
                        }
                    }
                    if !model.hasAPIKey {
                        LabeledContent("API key") {
                            Button("Add Key…") { WindowCoordinator.shared.showSettings(tab: .text) }
                        }
                    }
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("GPT-4o models usually recognize speech and terms more accurately than Whisper. For the fastest results without the internet, use Large v3 Turbo on this Mac.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshModels() }
    }
}

private struct ModelRow: View {
    @Environment(AppModel.self) private var model
    let info: WhisperModelInfo

    private var isSelected: Bool { model.settings.whisperModel == info.kind }

    var body: some View {
        HStack(spacing: 12) {
            if info.kind.isOffered {
                Button {
                    model.settings.whisperModel = info.kind
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Use this model"))
            } else {
                Image(systemName: "archivebox")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Labels.model(info.kind)).font(.body.weight(.medium))
                    Text(ByteCountFormatter.string(fromByteCount: Int64(info.kind.approximateSizeMB) * 1_000_000, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(Labels.modelDescription(info.kind)).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let download = model.downloads[info.kind] {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: download.fraction)
                        .frame(width: 150)
                    DownloadCaption(download: download)
                }
                Button {
                    model.cancelDownload(info.kind)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Cancel download"))
            } else if info.isInstalled {
                Label("Installed", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([info.url]) }
                    Button("Delete", role: .destructive) { model.deleteModel(info.kind) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Button("Download") { model.download(info.kind) }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { model.settings.whisperModel = info.kind }
    }
}

extension URL {
    var abbreviatingWithTildeInPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// "37% · 212 MB of 574 MB"
struct DownloadCaption: View {
    let download: DownloadProgress

    var body: some View {
        Text("\(Int(download.fraction * 100))% · \(Self.megabytes(download.receivedBytes)) of \(Self.megabytes(download.totalBytes))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    static func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
