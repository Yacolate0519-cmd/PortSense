import Foundation

/// Full command line + cwd for a PID, used to attribute listening ports.
struct PidEnrichment: Sendable {
    var command: String
    var cwd: String?
}

/// Enumerates developer-relevant running processes via `ps`, and provides
/// batched per-PID enrichment for port attribution. Ported from
/// `process-scanner.ts`.
enum ProcessScanner {
    private static let devProcessNames: Set<String> = [
        "node", "python", "python3", "ruby", "java", "go", "deno", "bun",
        "docker", "ollama", "claude", "electron", "chromium",
        "zsh", "bash", "fish", "gitstatusd",
    ]

    private static let devProcessPrefixes = ["python3.", "com.docker.", "code helper", "ollama"]

    /// macOS `ps comm=` truncates to 16 chars, so a GUI app's executable path
    /// comes back as junk. Derive a clean, human-readable name from the full
    /// command instead.
    static func cleanProcessName(comm: String, command: String) -> String {
        let firstToken = command
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first.map(String.init) ?? ""
        let source = firstToken.isEmpty ? comm : firstToken

        // .app bundle → use the (innermost) bundle name.
        if let range = source.range(of: ".app/", options: .backwards) {
            let before = String(source[source.startIndex..<range.lowerBound])
            if let appName = before.split(separator: "/").last { return String(appName) }
        }

        // Otherwise the executable basename, stripping a login-shell leading dash.
        var base = source.split(separator: "/").last.map(String.init) ?? source
        if base.hasPrefix("-") { base.removeFirst() }
        if !base.isEmpty { return base }
        return comm.isEmpty ? "unknown" : comm
    }

    private static func isDevProcess(name: String, rssKB: Int, cpuPct: Double) -> Bool {
        let lower = name.lowercased()
        if devProcessNames.contains(lower) { return true }
        for prefix in devProcessPrefixes where lower.hasPrefix(prefix) { return true }
        if rssKB > 50 * 1024 { return true } // > 50 MB
        if cpuPct > 1 { return true }
        return false
    }

    // MARK: - ps parsing

    private struct RawPsEntry {
        let pid: Int
        let ppid: Int
        let cpu: Double
        let rssKB: Int
        let name: String
        let command: String
    }

    private static func parsePs(_ raw: String) -> [RawPsEntry] {
        var entries: [RawPsEntry] = []
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Columns: pid ppid %cpu rss comm command(rest)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if parts.count < 5 { continue }

            guard let pid = Int(parts[0]), let ppid = Int(parts[1]) else { continue }
            let cpu = Double(parts[2]) ?? 0
            let rssKB = Int(parts[3]) ?? 0
            let comm = parts[4]
            let command = parts.count > 5 ? parts[5...].joined(separator: " ") : comm
            let name = cleanProcessName(comm: comm, command: command)

            entries.append(RawPsEntry(pid: pid, ppid: ppid, cpu: cpu, rssKB: rssKB, name: name, command: command))
        }
        return entries
    }

    // MARK: - Public API

    static func list() -> [DevProcess] {
        let raw = CommandRunner.run("/bin/ps", ["-axo", "pid=,ppid=,%cpu=,rss=,comm=,command="])
        let all = parsePs(raw)

        // pid → name map for parent lookup
        var pidToName: [Int: String] = [:]
        for e in all { pidToName[e.pid] = e.name }

        var result: [DevProcess] = []
        for e in all {
            guard isDevProcess(name: e.name, rssKB: e.rssKB, cpuPct: e.cpu) else { continue }
            let parentName = pidToName[e.ppid]
            let summary = Attribution.summarize(
                AttributionInput(name: e.name, command: e.command, cwd: nil, parentName: parentName)
            )
            let memoryMB = (Double(e.rssKB) / 1024 * 10).rounded() / 10
            result.append(DevProcess(
                pid: e.pid, name: e.name, command: e.command, summary: summary,
                cpu: e.cpu, memoryMB: memoryMB, parentPid: e.ppid
            ))
        }

        // Sort by memory descending, cap at 200.
        result.sort { $0.memoryMB > $1.memoryMB }
        return Array(result.prefix(200))
    }

    /// Fetch full command lines + cwd for a set of PIDs in two batched system
    /// calls (one `ps -ww`, one `lsof`). This is what lets port attribution
    /// recognise tools like Vite and the owning project directory.
    static func enrichments(for pids: [Int]) -> [Int: PidEnrichment] {
        var map: [Int: PidEnrichment] = [:]
        let unique = Array(Set(pids)).filter { $0 > 0 }
        if unique.isEmpty { return map }
        let pidList = unique.map(String.init).joined(separator: ",")

        // Full command lines via a single ps call. -ww prevents truncation.
        let psRaw = CommandRunner.run("/bin/ps", ["-ww", "-p", pidList, "-o", "pid=,command="])
        for line in psRaw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let spaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = String(trimmed[trimmed.startIndex..<spaceIdx])
            let command = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            if let pid = Int(pidStr), !command.isEmpty {
                map[pid] = PidEnrichment(command: command, cwd: nil)
            }
        }

        // cwd for all PIDs via a single lsof call (-Fpn stream of p<pid>/n<path>).
        let lsofRaw = CommandRunner.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pidList, "-Fpn"])
        var currentPid = 0
        for line in lsofRaw.split(separator: "\n") {
            guard let code = line.first else { continue }
            let value = String(line.dropFirst())
            if code == "p" {
                currentPid = Int(value) ?? 0
            } else if code == "n", currentPid > 0 {
                let path = value.trimmingCharacters(in: .whitespaces)
                if !path.isEmpty {
                    if var existing = map[currentPid] {
                        existing.cwd = path
                        map[currentPid] = existing
                    } else {
                        map[currentPid] = PidEnrichment(command: "", cwd: path)
                    }
                }
            }
        }

        return map
    }
}
