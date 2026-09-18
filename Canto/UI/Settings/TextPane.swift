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
                    ForEach(TextProcessingMode.choices, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Labels.processing(mode))
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
                Picker("Skill", selection: $model.settings.skill) {
                    Text("None").tag(String?.none)
                    ForEach(model.skills) { skill in
                        Text(skill.name).tag(Optional(skill.fileName))
                    }
                }
                Picker("Runs on", selection: $model.settings.aiProvider) {
                    Text("OpenAI").tag(AIProvider.openAI)
                    Text("Local server").tag(AIProvider.localServer)
                }
                if model.settings.aiProvider == .localServer {
                    TextField("Server", text: $model.settings.aiServerURL, prompt: Text(verbatim: "http://localhost:11434/v1"))
                    TextField("Model", text: $model.settings.aiServerModel, prompt: Text(verbatim: "qwen2.5:7b"))
                }
                LabeledContent {
                    HStack {
                        Button("Import…") { model.importSkill() }
                        Button("Open Folder") { model.openSkillsFolder() }
                        Button {
                            model.refreshSkills()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(Text("Reload skills"))
                    }
                } label: {
                    EmptyView()
                }
            } header: {
                Text("AI skill")
            } footer: {
                if model.settings.aiProvider == .localServer {
                    Text("Ollama: http://localhost:11434/v1, LM Studio: http://localhost:1234/v1. The text stays on your Mac.")
                } else {
                    Text("A skill is a Markdown file with instructions for the AI: clean up, organize, fix technical terms, translate. It runs after the cleanup and adds about a second.")
                }
            }

            Section("Cleanup") {
                Toggle(isOn: $model.settings.spokenPunctuation) {
                    Text("Spoken punctuation")
                    Text("Say “comma”, “period” or “new paragraph” to insert them.")
                }
                Picker("Numbers", selection: $model.settings.numberFormat) {
                    Text("As dictated").tag(NumberFormat.asHeard)
                    Text("Digits: 25").tag(NumberFormat.digits)
                    Text("Words: twenty-five").tag(NumberFormat.words)
                }
                Toggle(isOn: $model.settings.currencySymbols) {
                    Text("Currency symbols")
                    Text("“50 dollars” becomes “$50”, “50 euros” becomes “50 €”.")
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
                Text("Needed for skills on OpenAI and for recognition with OpenAI. Local recognition works without it.")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshSkills() }
        .keychainKeyChooser()
    }

    private func save() {
        model.saveAPIKey(keyDraft)
        keyDraft = ""
    }
}
