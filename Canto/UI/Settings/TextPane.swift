import SwiftUI
import CantoCore

struct TextPane: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Processing", selection: $model.settings.textProcessingMode) {
                    ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(Labels.processing(mode))
                                if mode.usesAI {
                                    Text("AI")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.purple.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.purple)
                                }
                            }
                            Text(Labels.processingDescription(mode))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text("Processing")
            }

            Section {
                Picker("Style", selection: $model.settings.aiStyle) {
                    Text("None").tag(String?.none)
                    ForEach(model.styles) { style in
                        Text(style.name).tag(Optional(style.fileName))
                    }
                }
                LabeledContent {
                    HStack {
                        Button("Import…") { model.importStyle() }
                        Button("Open Folder") { model.openStylesFolder() }
                        Button {
                            model.refreshStyles()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(Text("Reload styles"))
                    }
                } label: {
                    EmptyView()
                }
            } header: {
                Text("AI style")
            } footer: {
                Text("A style is a Markdown file with extra instructions for the AI, such as tone or terminology.")
            }
            .disabled(!model.settings.textProcessingMode.usesAI)

            Section("Cleanup") {
                Toggle(isOn: $model.settings.spokenPunctuation) {
                    Text("Spoken punctuation")
                    Text("Say “comma”, “period” or “new paragraph” to insert them.")
                }
                Toggle(isOn: $model.settings.numbersAsWords) {
                    Text("Write numbers as words")
                    Text("“42” becomes “forty-two”.")
                }
            }

            Section {
                if model.hasAPIKey {
                    LabeledContent("API key") {
                        HStack {
                            Label("Saved in the keychain", systemImage: "key.fill").foregroundStyle(.secondary)
                            Button("Remove", role: .destructive) { model.removeAPIKey() }
                        }
                    }
                } else {
                    LabeledContent("API key") {
                        HStack {
                            SecureField("API key", text: $keyDraft, prompt: Text("sk-…"))
                                .labelsHidden()
                                .frame(width: 220)
                                .onSubmit(save)
                            Button("Save", action: save)
                                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    LabeledContent {
                        HStack {
                            Button("Find in Keychain…") { model.findAPIKeyInKeychain() }
                            Link("Get a Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        }
                    } label: {
                        if let message = model.keychainSearchMessage {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Needed for AI processing and for recognition with OpenAI. Local recognition works without it.")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshStyles() }
        .keychainKeyChooser()
    }

    private func save() {
        model.saveAPIKey(keyDraft)
        keyDraft = ""
    }
}
