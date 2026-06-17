import SwiftUI
import AppKit

enum Tab: String, CaseIterable {
    case ports = "Ports"
    case processes = "Processes"
}

/// A process the user has asked to kill (drives the confirmation alerts).
struct KillTarget: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let command: String
    let summary: String
    let port: Int?
}

struct ContentView: View {
    @EnvironmentObject private var store: ScannerStore
    @State private var tab: Tab = .ports
    @State private var search = ""
    @State private var now = Date()

    // Two-stage kill flow.
    @State private var confirmTarget: KillTarget?
    @State private var forceTarget: KillTarget?
    @State private var killError: String?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            picker
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380, height: 540)
        .task { await store.run() }
        .onReceive(ticker) { now = $0 }
        .onChange(of: tab) { _ in search = "" }
        // Stage 1 — graceful kill confirmation.
        .alert("Kill \(confirmTarget?.name ?? "this process")?",
               isPresented: bool($confirmTarget),
               presenting: confirmTarget) { target in
            Button("Cancel", role: .cancel) {}
            Button("Kill Process", role: .destructive) { performKill(target, force: false) }
        } message: { target in
            Text(killMessage(target))
        }
        // Stage 2 — force quit confirmation (only if SIGTERM didn't work).
        .alert("Force quit \(forceTarget?.name ?? "this process")?",
               isPresented: bool($forceTarget),
               presenting: forceTarget) { target in
            Button("Cancel", role: .cancel) {}
            Button("Force Quit", role: .destructive) { performKill(target, force: true) }
        } message: { target in
            Text("A graceful quit signal didn’t stop \(target.name) (PID \(target.pid)). Force quit terminates it immediately and any unsaved work may be lost.")
        }
        // Error feedback.
        .alert("Couldn’t kill process",
               isPresented: Binding(get: { killError != nil }, set: { if !$0 { killError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(killError ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Text("Port Sense")
                .font(.headline)
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Menu {
                Button("Quit Port Sense") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var picker: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch tab {
            case .ports:
                PortsListView(ports: store.ports) { confirmTarget = $0 }
            case .processes:
                ProcessesListView(processes: store.processes, search: search) { confirmTarget = $0 }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = store.lastUpdated {
                Text("Updated \(relativeTime(updated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if tab == .processes {
                TextField("Search…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    // MARK: - Kill flow

    private func performKill(_ target: KillTarget, force: Bool) {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ProcessController.release(pid: Int32(target.pid), force: force)
            }.value

            switch result {
            case .ok:
                await store.refresh()
            case .needsForce:
                forceTarget = target
            case .failed(let message):
                killError = message
            }
        }
    }

    private func killMessage(_ target: KillTarget) -> String {
        let head = target.port != nil ? "Port \(target.port!) · PID \(target.pid)" : "PID \(target.pid)"
        return "\(head)\n\(target.command)"
    }

    // MARK: - Helpers

    /// Bridges an optional `Identifiable` into the `isPresented` Bool an alert needs.
    private func bool<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil },
                set: { if !$0 { binding.wrappedValue = nil } })
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }
}
