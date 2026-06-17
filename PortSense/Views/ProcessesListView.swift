import SwiftUI

struct ProcessesListView: View {
    let processes: [DevProcess]
    let search: String
    let onKill: (KillTarget) -> Void

    @State private var hoveredPID: Int?

    private var filtered: [DevProcess] {
        let q = search.lowercased()
        guard !q.isEmpty else { return processes }
        return processes.filter {
            String($0.pid).contains(q) ||
            $0.name.lowercased().contains(q) ||
            $0.command.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q)
        }
    }

    var body: some View {
        if filtered.isEmpty {
            EmptyStateView(title: search.isEmpty ? "No processes" : "No matching processes",
                           subtitle: search.isEmpty ? nil : "Try a different search term.")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { proc in
                        ProcessRow(proc: proc, hovered: hoveredPID == proc.pid, onKill: onKill)
                            .onHover { inside in
                                if inside { hoveredPID = proc.pid }
                                else if hoveredPID == proc.pid { hoveredPID = nil }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ProcessRow: View {
    let proc: DevProcess
    let hovered: Bool
    let onKill: (KillTarget) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(proc.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)

            if proc.summary.lowercased() != proc.name.lowercased() {
                Text(proc.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if hovered {
                RowActionButton(systemName: "trash", help: "Kill process", tint: .red) {
                    onKill(KillTarget(pid: proc.pid, name: proc.name,
                                      command: proc.command, summary: proc.summary, port: nil))
                }
            } else {
                HStack(spacing: 10) {
                    Label("\(Int(proc.memoryMB)) MB", systemImage: "memorychip")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if proc.cpu > 1 {
                        Label(String(format: "%.0f%%", proc.cpu), systemImage: "cpu")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovered ? Color.primary.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
    }
}
