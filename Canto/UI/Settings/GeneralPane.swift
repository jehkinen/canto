import SwiftUI
import CantoCore

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var appLanguage = AppLanguage.current

    var body: some View {
        @Bindable var model = model
        Form {
            if !model.setupIssues.isEmpty {
                Section {
                    ForEach(model.setupIssues) { issue in
                        LabeledContent {
                            if let action = issue.action {
                                Button("Fix") { NoticeActions.perform(action) }
                            }
                        } label: {
                            Label {
                                Text(issue.message)
                            } icon: {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Setup")
                }
            }

            Section {
                Toggle("Enable dictation", isOn: $model.settings.isEnabled)
                Toggle("Open Canto at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                        } catch {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            Section("Feedback") {
                Toggle("Show the recording overlay", isOn: $model.settings.showRecordingHUD)
                Toggle("Play sounds", isOn: $model.settings.playSounds)
            }

            Section {
                Toggle("Keep a history of transcripts", isOn: $model.settings.keepHistory)
                LabeledContent("Saved transcripts") {
                    HStack {
                        Text("\(model.history.count)").foregroundStyle(.secondary)
                        Button("Show History…") { WindowCoordinator.shared.showHistory() }
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("History stays on this Mac. Up to 200 recent transcripts are kept.")
            }

            Section {
                Picker("Language", selection: $appLanguage) {
                    Text("System").tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Русский").tag(AppLanguage.russian)
                    Text("עברית").tag(AppLanguage.hebrew)
                }
                .onChange(of: appLanguage) { _, language in language.apply() }
                if appLanguage != AppLanguage.launched {
                    LabeledContent {
                        Button("Restart Canto") { AppLanguage.relaunch() }
                    } label: {
                        Text("The new language is used after a restart.").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Interface")
            }

            Section {
                Button("Show Welcome Guide…") { WindowCoordinator.shared.showWelcome() }
            }
        }
        .formStyle(.grouped)
    }
}

enum AppLanguage: String {
    case system, english = "en", russian = "ru", hebrew = "he"

    static let launched = current

    static var current: AppLanguage {
        guard let languages = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        if first.hasPrefix("ru") { return .russian }
        if first.hasPrefix("he") { return .hebrew }
        return .english
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
