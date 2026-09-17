import SwiftUI

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppGlyph(size: 88)
                .shadow(color: .purple.opacity(0.3), radius: 18, y: 8)
            Text("Canto").font(.largeTitle.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Dictate anywhere on your Mac. Speech is recognized on device with Whisper, cleaned up and typed into the app you are using.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
            VStack(spacing: 4) {
                Text("Built with whisper.cpp (MIT) and libfvad (BSD).")
                Link("whisper.cpp on GitHub", destination: URL(string: "https://github.com/ggml-org/whisper.cpp")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}
