import SwiftUI

/// Live bars that breathe with the microphone level.
struct Waveform: View {
    var level: Float
    var barCount = 24
    var color: Color = Theme.listening
    var maxHeight: CGFloat = 36

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [color, Theme.blue], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: height(for: index, time: time))
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }

    private func height(for index: Int, time: TimeInterval) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let envelope = 1 - pow(abs(Double(index) - center) / (center + 1), 2) * 0.7
        let wobble = (sin(time * 9 + Double(index) * 0.8) + sin(time * 5.3 + Double(index) * 1.7)) / 4 + 0.5
        let amplitude = Double(min(max(level, 0), 1))
        let value = 0.12 + amplitude * envelope * (0.35 + 0.65 * wobble)
        return max(3, maxHeight * CGFloat(min(value, 1)))
    }
}

/// A compact segmented meter for the microphone test.
struct LevelMeter: View {
    var level: Float
    var segments = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Float(index) / Float(segments)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(level > threshold ? color(for: index) : Color.secondary.opacity(0.18))
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityValue(Text("\(Int(level * 100)) %"))
    }

    private func color(for index: Int) -> Color {
        switch Double(index) / Double(segments) {
        case ..<0.65: .green
        case ..<0.85: .yellow
        default: .red
        }
    }
}
