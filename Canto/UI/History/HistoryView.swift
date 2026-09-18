import SwiftUI
import CantoCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection = Set<TranscriptEntry.ID>()
    @State private var confirmClear = false

    private var entries: [TranscriptEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.history }
        return model.history.filter {
            $0.text.localizedCaseInsensitiveContains(trimmed) || ($0.appName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Button("Copy") { copySelection() }
                    .disabled(selection.isEmpty)
                Button("Delete") {
                    model.deleteHistory(selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Button("Clear All…") { confirmClear = true }
                    .disabled(model.history.isEmpty)
            }
            .padding(10)

            Divider()

            if model.history.isEmpty {
                ContentUnavailableView("No Transcripts Yet", systemImage: "waveform",
                                       description: Text("Everything you dictate appears here."))
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(selection: $selection) {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(group.day.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry)
                                    .tag(entry.id)
                                    .contextMenu {
                                        Button("Copy") { model.copy(entry) }
                                        Button("Delete", role: .destructive) { model.deleteHistory([entry.id]) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onCopyCommand {
                    selectedEntries.map { NSItemProvider(object: $0.text as NSString) }
                }
                .onDeleteCommand {
                    model.deleteHistory(selection)
                    selection.removeAll()
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { model.clearHistory() }
        }
    }

    private var selectedEntries: [TranscriptEntry] {
        model.history.filter { selection.contains($0.id) }
    }

    private func copySelection() {
        TextInserter.copyToPasteboard(selectedEntries.map(\.text).joined(separator: "\n\n"))
    }

    private var groupedByDay: [(day: Date, entries: [TranscriptEntry])] {
        let calendar = Calendar.current
        var groups: [(day: Date, entries: [TranscriptEntry])] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if groups.last?.day == day {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((day, [entry]))
            }
        }
        return groups
    }
}

private struct HistoryRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .textSelection(.enabled)
                .lineLimit(6)
            if let recognized = entry.recognized {
                Label {
                    Text(recognized).textSelection(.enabled).lineLimit(4)
                } icon: {
                    Image(systemName: "waveform")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(Text("What the model heard, before punctuation, numbers and the skill"))
            }
            HStack(spacing: 6) {
                Text(entry.date, style: .time)
                if let app = entry.appName {
                    Text("·")
                    Text(app)
                }
                Text("·")
                Text(Duration.seconds(entry.duration), format: .time(pattern: .minuteSecond))
                if let latency = entry.latency {
                    Text("·")
                    Label {
                        Text(Duration.milliseconds(Int(latency * 1000)).formatted(.units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: 1))))
                    } icon: {
                        Image(systemName: "bolt.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .help(Text("Time from the end of the phrase to the inserted text"))
                }
                if let skill = entry.skill {
                    Text("·")
                    Label(skill, systemImage: "sparkles").labelStyle(.titleAndIcon)
                } else if entry.processingMode.usesAI {
                    Text("·")
                    Label("AI", systemImage: "sparkles").labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
