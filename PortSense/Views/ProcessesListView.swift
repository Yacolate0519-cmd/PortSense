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
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { proc in
                        ProcessRow(proc: proc, hovered: hoveredPID == proc.pid, onKill: onKill)
                            .onHover { inside in
                                if inside { hoveredPID = proc.pid }
                                else if hoveredPID == proc.pid { hoveredPID = nil }
                            }
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
}

private struct ProcessRow: View {
    let proc: DevProcess
    let hovered: Bool
    let onKill: (KillTarget) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(proc.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)

            if proc.summary.lowercased() != proc.name.lowercased() {
                Text(proc.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if hovered {
                Button {
                    onKill(KillTarget(pid: proc.pid, name: proc.name,
                                      command: proc.command, summary: proc.summary, port: nil))
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Kill process")
            } else {
                HStack(spacing: 10) {
                    Label("\(Int(proc.memoryMB)) MB", systemImage: "memorychip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .help("Memory (RAM) in use")
                    if proc.cpu > 1 {
                        Label(String(format: "%.1f%%", proc.cpu), systemImage: "cpu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .help("CPU usage")
                    }
                }
                .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .background(hovered ? Color.primary.opacity(0.06) : Color.clear)
    }
}
