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
                LazyVStack(spacing: 0) {
                    ForEach(ports) { port in
                        PortRow(port: port, hovered: hoveredID == port.id, onKill: onKill)
                            .onHover { inside in
                                if inside { hoveredID = port.id }
                                else if hoveredID == port.id { hoveredID = nil }
                            }
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
}

private struct PortRow: View {
    let port: PortInfo
    let hovered: Bool
    let onKill: (KillTarget) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: port.bindAddress == "localhost" ? "lock.fill" : "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .help(port.bindAddress == "localhost" ? "Listening on localhost only" : "Listening on \(port.bindAddress)")

            Text(String(port.port))
                .font(.body.weight(.bold))
                .monospacedDigit()

            Text(port.summary)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if hovered {
                Button {
                    if let url = URL(string: "http://localhost:\(port.port)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open http://localhost:\(port.port)")

                Button {
                    onKill(KillTarget(pid: port.pid, name: port.processName,
                                      command: port.command, summary: port.summary, port: port.port))
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Kill process")
            } else if port.processName.lowercased() != port.summary.lowercased() {
                Text(port.processName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .background(hovered ? Color.primary.opacity(0.06) : Color.clear)
    }
}
