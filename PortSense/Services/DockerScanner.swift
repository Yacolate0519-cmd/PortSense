import Foundation

/// A published (host-mapped) port of a Docker container.
struct DockerPort: Sendable, Hashable {
    let hostPort: Int
    let containerPort: Int
    let proto: String
}

/// A running Docker container and its published ports.
struct DockerContainer: Identifiable, Sendable {
    var id: String { containerID }
    let containerID: String
    let name: String
    let image: String
    let status: String        // e.g. "Up 2 hours"
    let isRunning: Bool
    let ports: [DockerPort]   // host-mapped ports only
    let project: String       // Compose project ("" if not part of one)
    let service: String       // Compose service name (falls back to container name)
}

/// Reads running Docker containers and their published ports via `docker ps`.
///
/// The `docker` CLI isn't at a fixed system path (it depends on how Docker was
/// installed), so we probe a few known locations rather than relying on `PATH`.
enum DockerScanner {
    /// Distinguishes "Docker missing" from "daemon down" from "no containers".
    enum Result: Sendable {
        case notInstalled
        case daemonUnavailable
        case containers([DockerContainer])
    }

    private static let candidatePaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/usr/bin/docker",
    ]

    static func dockerPath() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func scan() -> Result {
        guard let docker = dockerPath() else { return .notInstalled }

        // Tab-separated: ID, Names, Image, Ports, Status, compose project, compose service.
        let format = [
            "{{.ID}}", "{{.Names}}", "{{.Image}}", "{{.Ports}}", "{{.Status}}",
            "{{.Label \"com.docker.compose.project\"}}",
            "{{.Label \"com.docker.compose.service\"}}",
        ].joined(separator: "\t")
        let (output, status) = CommandRunner.runWithStatus(
            docker, ["ps", "--format", format], timeout: 5
        )

        // Non-zero exit usually means the daemon isn't running.
        if status != 0 { return .daemonUnavailable }

        let containers = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0)) }
        return .containers(containers)
    }

    // MARK: - Parsing

    private static func parseLine(_ line: String) -> DockerContainer? {
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 5 else { return nil }
        let statusText = fields[4]
        let name = fields[1]
        let project = fields.count > 5 ? fields[5] : ""
        let serviceRaw = fields.count > 6 ? fields[6] : ""
        return DockerContainer(
            containerID: fields[0],
            name: name,
            image: fields[2],
            status: statusText,
            isRunning: statusText.lowercased().hasPrefix("up"),
            ports: parsePorts(fields[3]),
            project: project,
            service: serviceRaw.isEmpty ? name : serviceRaw
        )
    }

    /// Parse a `.Ports` string such as
    /// `0.0.0.0:5432->5432/tcp, :::5432->5432/tcp, 6379/tcp`
    /// keeping only published (host-mapped) entries, de-duplicated.
    private static func parsePorts(_ raw: String) -> [DockerPort] {
        var seen = Set<DockerPort>()
        var result: [DockerPort] = []

        for entry in raw.split(separator: ",") {
            let part = entry.trimmingCharacters(in: .whitespaces)
            // Only published ports have a "host->container" arrow.
            guard let arrow = part.range(of: "->") else { continue }

            let left = String(part[part.startIndex..<arrow.lowerBound])   // 0.0.0.0:5432
            let right = String(part[arrow.upperBound...])                 // 5432/tcp

            guard let hostPort = Int(left.split(separator: ":").last.map(String.init) ?? "") else { continue }
            let rightParts = right.split(separator: "/")
            guard let containerPort = Int(rightParts.first.map(String.init) ?? "") else { continue }
            let proto = rightParts.count > 1 ? String(rightParts[1]) : "tcp"

            let dp = DockerPort(hostPort: hostPort, containerPort: containerPort, proto: proto)
            if seen.insert(dp).inserted { result.append(dp) }
        }

        return result.sorted { $0.hostPort < $1.hostPort }
    }
}
