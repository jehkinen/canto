import SwiftUI

/// Terms as removable chips plus a field to add more (commas add several at once).
struct VocabularyEditor: View {
    @Binding var terms: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !terms.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(terms, id: \.self) { term in
                        TermChip(term: term) {
                            terms.removeAll { $0 == term }
                        }
                    }
                }
            }
            HStack {
                TextField("Add a word", text: $draft, prompt: Text("For example, Kubernetes"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func add() {
        for piece in draft.split(separator: ",") {
            let term = piece.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) else { continue }
            terms.append(term)
        }
        draft = ""
    }
}

private struct TermChip: View {
    let term: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(term)
                .font(.callout)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Remove"))
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .background(Theme.violet.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.violet.opacity(0.25), lineWidth: 0.5))
        .onHover { hovering = $0 }
    }
}

/// Lays children out left to right, wrapping to the next line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
