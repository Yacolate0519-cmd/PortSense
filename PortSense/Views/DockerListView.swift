import SwiftUI
import AppKit

/// Containers sharing a Compose project, shown together as one section.
private struct DockerGroup: Identifiable {
    var id: String { title }
    let title: String
    let services: [DockerContainer]
}

struct DockerListView: View {
    let result: DockerScanner.Result

    @State private var hoveredID: String?

    var body: some View {
        switch result {
        case .notInstalled:
            EmptyStateView(title: "Docker not found",
                           subtitle: "Install Docker to see container ports here.")
        case .daemonUnavailable:
            EmptyStateView(title: "Docker isn’t running",
                           subtitle: "Start your Docker engine (Docker Desktop, OrbStack, …) to see containers.")
        case .containers(let containers):
            if containers.isEmpty {
                EmptyStateView(title: "No running containers",
                               subtitle: "Containers started with published ports appear here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(groups(containers)) { group in
                            Section {
                                ForEach(group.services) { service in
                                    DockerServiceRow(container: service, hovered: hoveredID == service.id)
                                        .onHover { inside in
                                            if inside { hoveredID = service.id }
                                            else if hoveredID == service.id { hoveredID = nil }
                                        }
                                }
                            } header: {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Group containers by Compose project; standalone containers form their own
    /// single-service group keyed by container name. Insertion order preserved.
    private func groups(_ containers: [DockerContainer]) -> [DockerGroup] {
        var order: [String] = []
        var map: [String: [DockerContainer]] = [:]
        for c in containers {
            let key = c.project.isEmpty ? c.name : c.project
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(c)
        }
        return order.map { key in
            let services = (map[key] ?? []).sorted {
                ($0.ports.first?.hostPort ?? Int.max) < ($1.ports.first?.hostPort ?? Int.max)
            }
            return DockerGroup(title: key, services: services)
        }
    }
}

private struct DockerServiceRow: View {
    let container: DockerContainer
    let hovered: Bool

    private var hostPortsText: String {
        container.ports.isEmpty ? "—" : container.ports.map { String($0.hostPort) }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(container.isRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
                .help(container.status)

            // Left: published host port(s).
            Text(hostPortsText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            // Right: service name (or open-in-browser on hover).
            if hovered, let first = container.ports.first {
                RowActionButton(systemName: "arrow.up.right",
                                help: "Open http://localhost:\(first.hostPort)") {
                    if let url = URL(string: "http://localhost:\(first.hostPort)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Text(container.service)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
