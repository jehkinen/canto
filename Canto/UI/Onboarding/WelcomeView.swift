import SwiftUI
import CantoCore

/// First-run guide: permissions, a speech model, the shortcut and a place to try it.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    @State private var step: Step
    @State private var tryText = ""
    @State private var keyDraft = ""

    init(startAt step: Step = .welcome, onFinish: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.onFinish = onFinish
    }

    enum Step: Int, CaseIterable {
        case welcome, permissions, recognition, shortcut
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .permissions: permissions
                case .recognition: recognition
                case .shortcut: shortcut
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))

            HStack {
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.self) { item in
                        Circle()
                            .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step != .welcome {
                    Button("Back") { move(-1) }
                        .controlSize(.large)
                }
                Button(step == .shortcut ? "Start Using Canto" : "Continue") {
                    step == .shortcut ? onFinish() : move(1)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
        .keychainKeyChooser()
    }

    private func move(_ delta: Int) {
        withAnimation(.smooth(duration: 0.3)) {
            step = Step(rawValue: step.rawValue + delta) ?? step
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            AppGlyph(size: 96)
                .shadow(color: .purple.opacity(0.35), radius: 24, y: 10)
            Text("Welcome to Canto").font(.largeTitle.weight(.semibold))
            Text("Dictate into any app on your Mac. Hold a shortcut, speak, and the text appears where your cursor is.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(symbol: "lock.shield", title: "Two permissions",
                      subtitle: "Canto needs to hear you and to type for you. You can change this later in System Settings.")
            PermissionRow(symbol: "mic.fill", tint: .red, title: "Microphone",
                          detail: "To record while you dictate.",
                          granted: model.microphoneAccess == .granted) {
                model.requestMicrophone()
            }
            PermissionRow(symbol: "accessibility", tint: .blue, title: "Accessibility",
                          detail: "To insert the text into the app you are using.",
                          granted: model.accessibilityGranted) {
                model.requestAccessibility()
            }
            Spacer()
        }
    }

    private var recognition: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            StepTitle(symbol: "waveform", title: "Speech recognition",
                      subtitle: "Recognize speech privately on this Mac, or with OpenAI.")
            Picker("Engine", selection: $model.settings.transcriptionProvider) {
                Text("On this Mac").tag(TranscriptionProvider.local)
                Text("OpenAI").tag(TranscriptionProvider.openAI)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.settings.transcriptionProvider == .local {
                VStack(spacing: 10) {
                    ForEach(WhisperModelKind.available, id: \.self) { kind in
                        WelcomeModelRow(kind: kind)
                    }
                }
            } else if model.hasAPIKey {
                Label("Your OpenAI API key is saved.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                HStack {
                    SecureField("API key", text: $keyDraft, prompt: Text("sk-…"))
                    Button("Save") {
                        model.saveAPIKey(keyDraft)
                        keyDraft = ""
                    }
                    .disabled(keyDraft.isEmpty)
                }
                HStack {
                    Button("Find in Keychain…") { model.findAPIKeyInKeychain() }
                        .buttonStyle(.link)
                    if let message = model.keychainSearchMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    private var shortcut: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            StepTitle(symbol: "keyboard", title: "Your dictation key",
                      subtitle: "Hold it while you speak and release to insert the text.")
            HStack {
                Text("Shortcut")
                Spacer()
                ShortcutRecorder(hotkey: $model.settings.hotkey) { model.isRecordingShortcut = $0 }
                    .disabled(model.settings.capsLockAsHotkey)
            }
            Toggle("Use Caps Lock as the dictation key", isOn: Binding(
                get: { model.settings.capsLockAsHotkey },
                set: { model.settings.setCapsLockAsHotkey($0) }))
            VStack(alignment: .leading, spacing: 6) {
                Text("Try it here").font(.headline)
                TextEditor(text: $tryText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 110)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer()
        }
    }
}

private struct StepTitle: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: action)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.default, value: granted)
    }
}

private struct WelcomeModelRow: View {
    @Environment(AppModel.self) private var model
    let kind: WhisperModelKind

    private var installed: Bool { model.models.first { $0.kind == kind }?.isInstalled ?? false }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.settings.whisperModel == kind ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(model.settings.whisperModel == kind ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Labels.model(kind)) · \(kind.approximateSizeMB) MB").font(.headline)
                Text(Labels.modelDescription(kind)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let download = model.downloads[kind] {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: download.fraction).frame(width: 130)
                    DownloadCaption(download: download)
                }
            } else if installed {
                Label("Ready", systemImage: "checkmark").foregroundStyle(.green)
            } else {
                Button("Download") {
                    model.settings.whisperModel = kind
                    model.download(kind)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.settings.whisperModel = kind }
        .onAppear { model.refreshModels() }
    }
}
