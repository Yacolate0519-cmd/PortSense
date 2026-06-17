import Foundation

/// A single listening TCP port and the process that owns it.
struct PortInfo: Identifiable, Sendable {
    var id: String { "\(port)-\(pid)" }
    let port: Int
    let pid: Int
    /// Cleaned, human-readable owner name (e.g. "node", "Notion").
    let processName: String
    /// Full command line (argv) used for attribution.
    let command: String
    /// Human-readable attribution (e.g. "open-slide (Vite dev server)").
    let summary: String
    /// "localhost", "all", or a literal host/IP.
    let bindAddress: String
}

/// A developer-relevant running process.
struct DevProcess: Identifiable, Sendable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let command: String
    let summary: String
    let cpu: Double
    let memoryMB: Double
    let parentPid: Int
}
