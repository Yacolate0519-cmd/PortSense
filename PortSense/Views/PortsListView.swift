import SwiftUI
import AppKit

struct PortsListView: View {
    let ports: [PortInfo]
    let onKill: (KillTarget) -> Void

    @State private var hoveredID: String?

    var body: some View {
        if ports.isEmpty {
            EmptyStateView(title: "No listening ports",
                           subtitle: "No TCP ports are currently listening.")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(ports) { port in
                        PortRow(port: port, hovered: hoveredID == port.id, onKill: onKill)
                            .onHover { inside in
                                if inside { hoveredID = port.id }
                                else if hoveredID == port.id { hoveredID = nil }
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

private struct PortRow: View {
    let port: PortInfo
    let hovered: Bool
    let onKill: (KillTarget) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(String(port.port))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(port.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if hovered {
                RowActionButton(systemName: "arrow.up.right", help: "Open http://localhost:\(port.port)") {
                    if let url = URL(string: "http://localhost:\(port.port)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                RowActionButton(systemName: "trash", help: "Kill process", tint: .red) {
                    onKill(KillTarget(pid: port.pid, name: port.processName,
                                      command: port.command, summary: port.summary, port: port.port))
                }
            } else if port.processName.lowercased() != port.summary.lowercased() {
                Text(port.processName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

/// A small borderless icon button revealed on row hover.
struct RowActionButton: View {
    let systemName: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
