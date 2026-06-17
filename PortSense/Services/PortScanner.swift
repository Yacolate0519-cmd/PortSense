import Foundation

/// A listening port as parsed straight from lsof, before enrichment.
private struct RawPort {
    let port: Int
    let pid: Int
    let command: String
    let bindAddress: String
}

/// Enumerates all TCP listening ports via `lsof`, then enriches and attributes
/// them. Ported from `port-scanner.ts` + the `ports:list` handler.
enum PortScanner {
    /// Full pipeline: lsof scan → batched PID enrichment → attribution.
    static func list() -> [PortInfo] {
        let raw = scan()
        let enrichments = ProcessScanner.enrichments(for: raw.map { $0.pid })

        return raw.map { rp in
            let enrich = enrichments[rp.pid]
            let fullCommand: String = {
                if let c = enrich?.command, !c.isEmpty { return c }
                return rp.command
            }()
            let processName = ProcessScanner.cleanProcessName(comm: rp.command, command: fullCommand)
            let summary = Attribution.summarize(
                AttributionInput(name: processName, command: fullCommand, cwd: enrich?.cwd)
            )
            return PortInfo(
                port: rp.port,
                pid: rp.pid,
                processName: processName,
                command: fullCommand,
                summary: summary,
                bindAddress: rp.bindAddress
            )
        }
    }

    private static func scan() -> [RawPort] {
        let output = CommandRunner.run(
            "/usr/sbin/lsof",
            ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
        )
        return parse(output)
    }

    /// Parse lsof -F field output. Records start with a letter code:
    /// p = PID, c = command, n = network address (e.g. *:8080, 127.0.0.1:3000).
    private static func parse(_ raw: String) -> [RawPort] {
        var results: [RawPort] = []
        var seen = Set<String>()
        var currentPid = 0
        var currentCommand = ""

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let code = line.first else { continue }
            let value = String(line.dropFirst())

            switch code {
            case "p":
                currentPid = Int(value) ?? 0
            case "c":
                currentCommand = value
            case "n":
                // value: *:3000 | 127.0.0.1:8080 | [::1]:5432 | [::]:80
                guard let lastColon = value.lastIndex(of: ":") else { continue }
                let rawHost = String(value[value.startIndex..<lastColon])
                let rawPort = String(value[value.index(after: lastColon)...])

                guard let port = Int(rawPort), port > 0, port <= 65535, currentPid != 0 else { continue }

                let cleanHost = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let bindAddress: String
                if cleanHost == "127.0.0.1" || cleanHost == "::1" || cleanHost == "localhost" {
                    bindAddress = "localhost"
                } else if cleanHost == "*" || cleanHost == "0.0.0.0" || cleanHost == "::" {
                    bindAddress = "all"
                } else {
                    bindAddress = cleanHost
                }

                let key = "\(port):\(currentPid)"
                if seen.contains(key) { continue }
                seen.insert(key)

                results.append(RawPort(port: port, pid: currentPid, command: currentCommand, bindAddress: bindAddress))
            default:
                break
            }
        }

        return results
    }
}
