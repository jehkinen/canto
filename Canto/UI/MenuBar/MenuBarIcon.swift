import SwiftUI

struct MenuBarIcon: View {
    let phase: DictationPhase
    let isEnabled: Bool

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(Text("Canto"))
    }

    private var symbol: String {
        guard isEnabled else { return "mic.slash" }
        switch phase {
        case .idle, .inserted: return "waveform"
        case .listening: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}
