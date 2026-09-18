import SwiftUI
import CantoCore

/// The panel under the menu bar icon: status, a live preview of dictation, quick controls
/// and the latest transcripts.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Every block has a fixed height: the menu bar window is sized once when it opens and
        // does not follow later content changes, so a growing panel would be clipped.
        VStack(alignment: .leading, spacing: 12) {
            header
            HeroCard()
                .frame(height: 150)
            quickControls
            recent
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 356)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            AppGlyph(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Canto").font(.headline)
                StatusLine()
            }
            Spacer()
            Toggle("Dictation", isOn: $model.settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(Text("Turn dictation on or off"))
        }
    }

    private var quickControls: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            QuickRow(symbol: "hand.tap", title: "Mode") {
                ValueMenu(title: model.settings.activationMode == .pushToTalk ? String(localized: "Hold") : String(localized: "Toggle")) {
                    Picker("Mode", selection: $model.settings.activationMode) {
                        Text("Hold").tag(ActivationMode.pushToTalk)
                        Text("Toggle").tag(ActivationMode.toggle)
                    }
                }
            }
            Divider().padding(.leading, 36)
            QuickRow(symbol: "mic", title: "Microphone") {
                ValueMenu(title: microphoneTitle) {
                    Picker("Microphone", selection: $model.settings.microphoneUID) {
                        Text("Default").tag(String?.none)
                        ForEach(model.devices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                    }
                }
            }
            Divider().padding(.leading, 36)
            QuickRow(symbol: "globe", title: "Language") {
                ValueMenu(title: model.settings.language == nil ? String(localized: "Auto") : Labels.language(model.settings.language)) {
                    Picker("Language", selection: $model.settings.language) {
                        ForEach(Labels.languages, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                }
            }
            Divider().padding(.leading, 36)
            QuickRow(symbol: "text.quote", title: "Text") {
                ValueMenu(title: String(localized: Labels.processingResource(model.settings.textProcessingMode))) {
                    Picker("Text", selection: $model.settings.textProcessingMode) {
                        ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                            Text(Labels.processing(mode)).tag(mode)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var microphoneTitle: String {
        guard let uid = model.settings.microphoneUID, let device = model.devices.first(where: { $0.uid == uid }) else {
            return String(localized: "Default")
        }
        return device.name
    }

    static func shortened(_ name: String, limit: Int = 20) -> String {
        name.count > limit ? String(name.prefix(limit - 1)) + "…" : name
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Show All") { WindowCoordinator.shared.showHistory() }
                    .buttonStyle(.link)
                    .font(.subheadline)
                    .disabled(model.history.isEmpty)
            }
            .frame(height: 18)
            if model.history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.title2).foregroundStyle(.tertiary)
                    Text("Your latest transcripts will appear here")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: RecentRow.height * 3)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.history.prefix(3)) { entry in
                        RecentRow(entry: entry)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: RecentRow.height * 3)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                WindowCoordinator.shared.showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            Button {
                WindowCoordinator.shared.showHistory()
            } label: {
                Label("History", systemImage: "clock")
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help(Text("Quit"))
            .accessibilityLabel(Text("Quit"))
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.callout)
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var text: LocalizedStringKey {
        guard model.settings.isEnabled else { return "Off" }
        switch model.phase {
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .inserted: return "Inserted"
        case .failed: return "Something went wrong"
        case .idle: return model.setupIssues.isEmpty ? "Ready" : "Needs setup"
        }
    }

    private var color: Color {
        guard model.settings.isEnabled else { return .secondary }
        switch model.phase {
        case .listening: return Theme.listening
        case .transcribing: return Theme.blue
        case .inserted: return .green
        case .failed: return .orange
        case .idle: return model.setupIssues.isEmpty ? .green : .orange
        }
    }
}

private struct HeroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            switch model.phase {
            case .listening where model.microphoneWarmingUp:
                ProgressView().controlSize(.regular).frame(height: 36)
                Text("Starting the microphone…").font(.callout)
                Text("Start speaking after the sound").font(.caption).foregroundStyle(.secondary)
            case .listening(let since):
                Waveform(level: model.level, barCount: 30, maxHeight: 44)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(since))), format: .time(pattern: .minuteSecond))
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                }
                Text(model.settings.activationMode == .pushToTalk ? "Release to insert" : "Press the shortcut again to finish")
                    .font(.caption).foregroundStyle(.secondary)
            case .transcribing:
                ProgressView().controlSize(.regular).frame(height: 36)
                Text("Turning speech into text…").font(.callout)
                HStack(spacing: 10) {
                    if let since = model.transcribingSince {
                        ElapsedTime(since: since)
                    }
                    Button("Cancel") { model.cancelTranscription() }
                        .controlSize(.small)
                }
            default:
                if let issue = model.setupIssues.first {
                    SetupIssueHero(issue: issue, remaining: model.setupIssues.count - 1)
                } else {
                    idleHint
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(heroTint.opacity(0.10).gradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(heroTint.opacity(0.18), lineWidth: 1)
        }
        .animation(.smooth(duration: 0.25), value: model.phase)
    }

    @ViewBuilder
    private var idleHint: some View {
                KeyCaps(hotkey: model.settings.hotkey, size: .large)
                    .frame(height: 44)
                    .opacity(model.settings.isEnabled ? 1 : 0.4)
                Text(model.settings.activationMode == .pushToTalk ? "Hold to dictate, release to insert" : "Press to start dictation, press again to finish")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.hotkeyConflict {
                    Label("This shortcut is used by another app", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
    }

    private var heroTint: Color {
        switch model.phase {
        case .listening: return Theme.listening
        case .transcribing: return Theme.blue
        default: return model.setupIssues.isEmpty ? .accentColor : .orange
        }
    }
}

private struct SetupIssueHero: View {
    let issue: Notice
    let remaining: Int

    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(.orange)
        Text(issue.message)
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
        HStack(spacing: 8) {
            if let action = issue.action {
                Button("Fix") { NoticeActions.perform(action) }
                    .controlSize(.small)
            }
            if remaining > 0 {
                Button {
                    WindowCoordinator.shared.showSettings(tab: .general)
                } label: {
                    Text("\(remaining) more")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}

@MainActor
enum NoticeActions {
    static func perform(_ action: Notice.Action) {
        switch action {
        case .openMicrophoneSettings: AppModel.shared.requestMicrophone()
        case .grantAccessibility: AppModel.shared.requestAccessibility()
        case .openModels: WindowCoordinator.shared.showSettings(tab: .recognition)
        case .openAPIKey: WindowCoordinator.shared.showSettings(tab: .text)
        }
    }
}

private struct QuickRow<Control: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 12)
            control
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 32)
    }
}

/// A System Settings–style value: plain text with an up-down chevron that opens a menu with the
/// choices. Unlike a pop-up button its width follows the text, so values line up on the right.
private struct ValueMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: 170, alignment: .trailing)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct RecentRow: View {
    static let height: CGFloat = 44

    @Environment(AppModel.self) private var model
    let entry: TranscriptEntry
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            model.copy(entry)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text).font(.callout).lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 4) {
                        if let app = entry.appName { Text(app) }
                        Text(entry.date.formatted(.relative(presentation: .named)))
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .secondary)
                    .opacity(hovering || copied ? 1 : 0)
            }
                .padding(.horizontal, 8)
            .frame(height: RecentRow.height)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("Copy"))
    }
}

/// The app icon, used as the mark in the panel, the guide and About.
struct AppGlyph: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Seconds spent waiting, shown once the wait gets noticeable.
struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(since))
            if seconds >= 3 {
                Text("\(seconds) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
