import Foundation
import SwiftUI

/// Owns the scanned data and drives the 4-second auto-refresh loop. Scanning
/// runs off the main actor; published results update the UI on the main actor.
@MainActor
final class ScannerStore: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var processes: [DevProcess] = []
    @Published var docker: DockerScanner.Result = .containers([])
    @Published var isLoading = true
    @Published var lastUpdated: Date?

    /// Run an initial scan, then refresh every 4 seconds until cancelled.
    /// Drive this from a SwiftUI `.task` so it cancels when the popover closes.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                break // cancelled
            }
        }
    }

    func refresh() async {
        // Run the blocking scans concurrently off the main actor.
        let portsHandle = Task.detached(priority: .utility) { PortScanner.list() }
        let processesHandle = Task.detached(priority: .utility) { ProcessScanner.list() }
        let dockerHandle = Task.detached(priority: .utility) { DockerScanner.scan() }

        let newPorts = await portsHandle.value
        let newProcesses = await processesHandle.value
        let newDocker = await dockerHandle.value

        ports = newPorts.sorted { $0.port < $1.port }
        processes = newProcesses
        docker = newDocker
        lastUpdated = Date()
        isLoading = false
    }
}
