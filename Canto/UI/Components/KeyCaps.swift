import SwiftUI
import CantoCore

/// A shortcut drawn as keyboard keys: ⌥ ⇧ F1.
struct KeyCaps: View {
    let hotkey: Hotkey
    var size: ControlSize = .regular

    var body: some View {
        HStack(spacing: size == .large ? 6 : 3) {
            ForEach(Array(KeyNames.symbols(for: hotkey).enumerated()), id: \.offset) { _, symbol in
                KeyCap(label: hotkey == .capsLock ? "⇪ Caps Lock" : symbol, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(KeyNames.description(for: hotkey)))
    }
}

struct KeyCap: View {
    let label: String
    var size: ControlSize = .regular

    var body: some View {
        Text(label)
            .font(size == .large ? .system(size: 17, weight: .medium, design: .rounded) : .system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, size == .large ? 10 : 6)
            .frame(minWidth: size == .large ? 34 : 22, minHeight: size == .large ? 32 : 20)
            .background {
                RoundedRectangle(cornerRadius: size == .large ? 7 : 5, style: .continuous)
                    .fill(.background.secondary)
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size == .large ? 7 : 5, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }
}
