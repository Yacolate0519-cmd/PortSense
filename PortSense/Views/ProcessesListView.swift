import SwiftUI

/// How the Processes list is ordered.
enum ProcessSort {
    case memory
    case cpu
}

struct ProcessesListView: View {
    let processes: [DevProcess]
    let search: String
    let sort: ProcessSort
    let onKill: (KillTarget) -> Void

    @State private var hoveredPID: Int?

    private var filtered: [DevProcess] {
        let q = search.lowercased()
        let matched = q.isEmpty ? processes : processes.filter {
            String($0.pid).contains(q) ||
            $0.name.lowercased().contains(q) ||
            $0.command.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q)
        }
        switch sort {
        case .memory: return matched.sorted { $0.memoryMB > $1.memoryMB }
        case .cpu:    return matched.sorted { $0.cpu > $1.cpu }
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

    private var showsSummary: Bool {
        !proc.summary.isEmpty && proc.summary.lowercased() != proc.name.lowercased()
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left — process name (left-aligned)
            Text(proc.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Middle — app description (centered); blank when same as the name
            Text(showsSummary ? proc.summary : "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)

            // Right — memory/CPU (never wraps), or kill on hover (right-aligned)
            Group {
                if hovered {
                    RowActionButton(systemName: "trash", help: "Kill process", tint: .red) {
                        onKill(KillTarget(pid: proc.pid, name: proc.name,
                                          command: proc.command, summary: proc.summary, port: nil))
                    }
                } else {
                    HStack(spacing: 8) {
                        Label("\(Int(proc.memoryMB)) MB", systemImage: "memorychip")
                            .help("Memory (RAM) in use")
                        Label(String(format: "%.0f%%", proc.cpu), systemImage: "cpu")
                            .help("CPU usage")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
