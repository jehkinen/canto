import SwiftUI
import CantoCore

struct DictationPane: View {
    @Environment(AppModel.self) private var model
    @State private var triggerDraft = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Mode", selection: $model.settings.activationMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hold to talk")
                        Text("Hold the shortcut while you speak, release to insert.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(ActivationMode.pushToTalk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Press to start and stop")
                        Text("Speak naturally: every pause inserts the phrase you just said.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(ActivationMode.toggle)
                }
                .pickerStyle(.radioGroup)

                LabeledContent("Shortcut") {
                    ShortcutRecorder(hotkey: $model.settings.hotkey) { recording in
                        model.isRecordingShortcut = recording
                    }
                    .disabled(model.settings.capsLockAsHotkey)
                }
                if model.hotkeyConflict {
                    Label("This shortcut is used by another app. Choose a different one.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                Toggle(isOn: Binding(get: { model.settings.capsLockAsHotkey },
                                     set: { model.settings.setCapsLockAsHotkey($0) })) {
                    Text("Use Caps Lock as the dictation key")
                    Text("While Canto runs, Caps Lock acts as F18 and becomes the shortcut. Turn this off or quit Canto to get Caps Lock back.")
                }
            } header: {
                Text("Shortcut")
            }

            Section {
                Picker("Microphone", selection: $model.settings.microphoneUID) {
                    Text(defaultMicrophoneTitle).tag(String?.none)
                    if !model.devices.isEmpty { Divider() }
                    ForEach(model.devices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                    if let uid = model.settings.microphoneUID, !model.devices.contains(where: { $0.uid == uid }) {
                        Text("Unavailable device").tag(Optional(uid))
                    }
                }
                LabeledContent("Input level") {
                    HStack(spacing: 10) {
                        LevelMeter(level: model.isMicrophoneTestRunning || model.isListening ? model.level : 0)
                            .frame(width: 180)
                        Button(model.isMicrophoneTestRunning ? "Stop" : "Test") {
                            model.isMicrophoneTestRunning ? model.stopMicrophoneTest() : model.startMicrophoneTest()
                        }
                        .disabled(model.isListening)
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("If the selected microphone is disconnected, Canto uses the system default.")
            }
            .onChange(of: model.settings.microphoneUID) {
                if model.isMicrophoneTestRunning {
                    model.stopMicrophoneTest()
                    model.startMicrophoneTest()
                }
            }

            Section {
                LabeledContent {
                    Picker("Insert text by", selection: $model.settings.insertionMethod) {
                        Text("Paste (⌘V)").tag(InsertionMethod.paste)
                        Text("Type letter by letter").tag(InsertionMethod.type)
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    HStack(spacing: 4) {
                        Text("Insert text by")
                        InfoButton(text: "Paste: Canto puts the text on the clipboard, presses ⌘V and then puts back what was on the clipboard before. Instant, works almost everywhere.\n\nType letter by letter: Canto types the text as if from the keyboard. Slower and may be affected by autocorrect, but the clipboard stays untouched. Useful where pasting is blocked.")
                    }
                }
                LabeledContent("Accessibility") {
                    if model.accessibilityGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { model.requestAccessibility() }
                    }
                }
            } header: {
                Text("Insertion")
            } footer: {
                Text("Both ways need Accessibility access. If Canto is already in that list but text is not inserted, remove it with “−” and allow it again.")
            }

            Section {
                Toggle("Press Return after a phrase", isOn: $model.settings.pressEnterOnTrigger)
                TextField("Phrase", text: $model.settings.enterTriggerPhrase, prompt: Text("for example “send it”"))
                    .disabled(!model.settings.pressEnterOnTrigger)
            } header: {
                Text("Send")
            } footer: {
                Text("End a dictation with this phrase to insert the text and press Return, for example to send a chat message.")
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.stopMicrophoneTest() }
    }

    private var defaultMicrophoneTitle: String {
        if let name = model.defaultDeviceName {
            return String(localized: "System default (\(name))")
        }
        return String(localized: "System default")
    }
}
