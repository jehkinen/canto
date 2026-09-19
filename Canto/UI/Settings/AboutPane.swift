import SwiftUI

struct AboutPane: View {
    @Environment(AppModel.self) private var model
    @State private var isChecking = false

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 14) {
            Spacer()
            AppGlyph(size: 88)
                .shadow(color: .purple.opacity(0.3), radius: 18, y: 8)
            Text("Canto").font(.largeTitle.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Check for Updates") {
                    isChecking = true
                    Task {
                        await model.checkForUpdates(userInitiated: true)
                        isChecking = false
                    }
                }
                .disabled(isChecking)
                if isChecking {
                    ProgressView().controlSize(.small)
                } else if let update = model.availableUpdate {
                    Link("Download \(update.version)", destination: update.pageURL)
                } else if let message = model.updateCheckMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            Toggle("Check for updates automatically", isOn: $model.settings.checkForUpdates)
                .toggleStyle(.checkbox)
                .help(Text("Once a day Canto asks GitHub whether a new version is out. Nothing about you is sent."))
            Text("Dictate anywhere on your Mac. Speech is recognized on device, cleaned up and typed into the app you are using.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            VStack(spacing: 4) {
                Text("© 2026 Andrei Bogdanov")
                Link("andydev.space", destination: URL(string: "https://andydev.space")!)
            }
            .padding(.top, 6)
            Spacer()
            Text("Built with whisper.cpp (MIT), FluidAudio (Apache 2.0), Silero VAD (MIT) and libfvad (BSD).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
}
