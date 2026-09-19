import SwiftUI

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppGlyph(size: 88)
                .shadow(color: .purple.opacity(0.3), radius: 18, y: 8)
            Text("Canto").font(.largeTitle.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
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
