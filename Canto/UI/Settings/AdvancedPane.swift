import SwiftUI
import CantoCore

struct AdvancedPane: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.settings.audioPreprocessing) {
                    Text("Clean up audio before recognition")
                    Text("Removes low rumble, evens out loudness and skips silent recordings.")
                }
            } header: {
                Text("Audio")
            }

            Section {
                MillisecondsSlider(title: "Pause that ends a phrase", value: $model.settings.silenceTimeoutMs, range: 200...3_000, step: 50)
                MillisecondsSlider(title: "Audio kept before speech", value: $model.settings.vadPreSpeechBufferMs, range: 50...2_000, step: 50)
                MillisecondsSlider(title: "Shortest phrase", value: $model.settings.vadMinimumSpeechMs, range: 50...2_000, step: 50)
                MillisecondsSlider(title: "Longest phrase", value: $model.settings.vadMaximumSegmentMs, range: 5_000..<120_001, step: 5_000)
            } header: {
                Text("Speech detection")
            } footer: {
                Text("The pause applies to Press to start and stop mode. Long phrases are split so each part is recognized quickly.")
            }

            Section {
                LabeledContent("Data folder") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppPaths.supportDirectory)
                    }
                }
                LabeledContent("Settings") {
                    Button("Reset to Defaults…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetSettings() }
        } message: {
            Text("Your models, history, skills and API key are kept.")
        }
    }
}

private struct MillisecondsSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    init(title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
    }

    init(title: LocalizedStringKey, value: Binding<Int>, range: Range<Int>, step: Int) {
        self.init(title: title, value: value, range: range.lowerBound...(range.upperBound - 1), step: step)
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                    .frame(width: 180)
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    private var formatted: String {
        value >= 1_000
            ? Duration.milliseconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: 1)))
            : Duration.milliseconds(value).formatted(.units(allowed: [.milliseconds], width: .abbreviated))
    }
}
