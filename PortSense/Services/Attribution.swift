import Foundation

/// Input for attribution: a raw process name plus context.
struct AttributionInput {
    let name: String
    let command: String
    var cwd: String? = nil
    var parentName: String? = nil
}

/// Maps a raw process name + command + context to a human-readable label.
/// Pure, side-effect-free logic (ported from the original `attribution.ts`).
enum Attribution {
    static func summarize(_ input: AttributionInput) -> String {
        let name = input.name
        let command = input.command
        let cwd = input.cwd
        let parentName = input.parentName
        let lower = name.lowercased()

        // Node.js variants
        if lower == "node" || lower == "node.js" {
            return attributeNode(command, cwd)
        }

        // Python variants
        if lower == "python" || lower == "python3" || isPythonVersioned(lower) {
            return attributePython(command, cwd)
        }

        // Shell processes
        if lower == "zsh" || lower == "bash" || lower == "fish" || lower == "sh" {
            return attributeShell(name, parentName)
        }

        // VS Code helper processes
        if ["code helper", "code helper (plugin)", "code helper (renderer)", "code helper (gpu)"].contains(lower) {
            return attributeCodeHelper(command)
        }

        // Ollama
        if lower == "ollama" || lower == "ollama serve" { return "Local Ollama API" }
        if lower == "ollama runner" { return "Ollama model runner" }

        // Docker
        if lower == "docker" || lower.hasPrefix("com.docker.") { return "Docker Desktop helper" }

        // Java
        if lower == "java" { return attributeJava(command) }

        // Ruby
        if lower == "ruby" {
            let cmd = command.lowercased()
            if cmd.contains("rails") { return "Ruby on Rails" }
            if cmd.contains("rspec") { return "RSpec" }
            if cmd.contains("rake") { return "Rake task" }
            return "Ruby process"
        }

        // Go
        if lower == "go" || lower == "go run" || lower == "go build" { return "Go process" }

        // Deno / Bun
        if lower == "deno" { return "Deno runtime" }
        if lower == "bun" { return "Bun runtime" }

        // Electron
        if lower == "electron" { return "Electron app\(projectSuffix(cwd))" }

        // Gitstatusd (Powerlevel10k)
        if lower == "gitstatusd" || lower.hasPrefix("gitstatusd-") { return "Powerlevel10k git status daemon" }

        // Claude
        if lower == "claude" { return "Claude process" }

        // Chromium
        if lower == "chromium" || lower == "chromium-browser" { return "Chromium browser" }

        // Default: strip path from name
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    // MARK: - Path helpers

    /// Last path component, ignoring trailing slashes.
    private static func lastDir(_ p: String?) -> String {
        guard let p, !p.isEmpty else { return "" }
        return p.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
    }

    private static func projectSuffix(_ cwd: String?) -> String {
        let dir = lastDir(cwd)
        return dir.isEmpty ? "" : " (\(dir))"
    }

    /// Prefer the cwd directory, else the directory above a `node_modules/`
    /// segment in the command.
    private static func projectName(_ command: String, _ cwd: String?) -> String {
        let fromCwd = lastDir(cwd)
        if !fromCwd.isEmpty { return fromCwd }
        if let r = command.range(of: "/node_modules/") {
            return lastDir(String(command[command.startIndex..<r.lowerBound]))
        }
        return ""
    }

    private static func labelWithProject(_ tool: String, _ command: String, _ cwd: String?) -> String {
        let proj = projectName(command, cwd)
        return proj.isEmpty ? tool : "\(proj) (\(tool))"
    }

    /// Normalise a path-like string, resolving "." and ".." segments.
    private static func normalizeSegments(_ p: String) -> [String] {
        var segs: [String] = []
        for raw in p.split(separator: "/", omittingEmptySubsequences: false) {
            let seg = String(raw)
            if seg.isEmpty || seg == "." { continue }
            if seg == ".." { if !segs.isEmpty { segs.removeLast() }; continue }
            segs.append(seg)
        }
        return segs
    }

    /// Extract the npm package/tool a node process is running, from the path
    /// after the last "/node_modules/" segment. Scoped packages surface the
    /// scope name (e.g. "@open-slide/core" → "open-slide").
    private static func nodePackageName(_ command: String) -> String {
        let marker = "/node_modules/"
        guard let r = command.range(of: marker, options: .backwards) else { return "" }
        let rest = firstToken(String(command[r.upperBound...]))
        var segs = normalizeSegments(rest)
        if segs.isEmpty { return "" }
        var i = 0
        if segs[i] == ".bin" { i += 1 }
        if i >= segs.count { return "" }
        if segs[i].hasPrefix("@") { return String(segs[i].dropFirst()) }
        return segs[i]
    }

    private static let knownSubcommands = ["preview", "dev", "serve", "start", "build", "watch"]

    private static func detectSubcommand(_ command: String) -> String {
        let tokens = command.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        for t in tokens.reversed() where knownSubcommands.contains(t) { return t }
        return ""
    }

    /// First whitespace-delimited token of a string.
    private static func firstToken(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init) ?? ""
    }

    /// First capture group of a regex, or nil.
    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func isPythonVersioned(_ s: String) -> Bool {
        s.range(of: "^python3?\\.\\d+$", options: .regularExpression) != nil
    }

    // MARK: - Node.js

    private static func attributeNode(_ command: String, _ cwd: String?) -> String {
        let cmd = command.lowercased()
        func withProj(_ tool: String) -> String { labelWithProject(tool, command, cwd) }

        if cmd.contains("vite") || cmd.contains("/vite") {
            if cmd.contains("preview") { return withProj("Vite preview") }
            return withProj("Vite dev server")
        }
        if cmd.contains("next") && (cmd.contains("start") || cmd.contains("dev")) { return withProj("Next.js server") }
        if cmd.contains("next") { return withProj("Next.js") }
        if cmd.contains("webpack") { return withProj("Webpack") }
        if cmd.contains("rollup") { return withProj("Rollup") }
        if cmd.contains("esbuild") { return withProj("esbuild") }
        if cmd.contains("vitest") { return withProj("Vitest") }
        if cmd.contains("jest") { return withProj("Jest") }
        if cmd.contains("mocha") { return withProj("Mocha") }
        if cmd.contains("ts-node") || cmd.contains("ts_node") { return withProj("ts-node") }
        if cmd.contains("tsx ") || cmd.hasSuffix("tsx") { return withProj("tsx") }
        if cmd.contains("electron") { return withProj("Electron app") }
        if cmd.contains("nodemon") { return withProj("nodemon") }
        if cmd.contains("pm2") { return withProj("PM2 process") }
        if cmd.contains("npm run") || cmd.contains("npm start") ||
            cmd.contains("pnpm run") || cmd.contains("yarn run") || cmd.contains("yarn start") {
            return withProj("npm/yarn script")
        }
        if cmd.contains("express") || cmd.contains("fastify") || cmd.contains("koa") {
            return withProj("Node.js server")
        }

        // Fall back to the actual npm package/tool the process is running.
        let pkg = nodePackageName(command)
        if !pkg.isEmpty {
            let sub = detectSubcommand(command)
            return sub.isEmpty ? pkg : "\(pkg) \(sub)"
        }

        return withProj("Node.js")
    }

    // MARK: - Python

    private static func attributePython(_ command: String, _ cwd: String?) -> String {
        let cmd = command.lowercased()
        let proj = projectSuffix(cwd)

        if cmd.contains("jupyter") { return "Jupyter\(proj)" }
        if cmd.contains("uvicorn") { return "Python: uvicorn\(proj)" }
        if cmd.contains("gunicorn") { return "Python: gunicorn\(proj)" }
        if cmd.contains("fastapi") { return "Python: FastAPI\(proj)" }
        if cmd.contains("flask") { return "Python: Flask\(proj)" }
        if cmd.contains("django") { return "Python: Django\(proj)" }
        if cmd.contains("pytest") { return "pytest\(proj)" }

        if let module = firstGroup("-m\\s+(\\S+)", in: command) {
            return "Python: \(module)\(proj)"
        }
        if let py = firstGroup("(\\S+\\.py)", in: command) {
            let scriptName = py.split(separator: "/").last.map(String.init) ?? py
            return "Python: \(scriptName)\(proj)"
        }

        return "Python\(proj)"
    }

    // MARK: - Shell

    private static func attributeShell(_ name: String, _ parentName: String?) -> String {
        let parent = (parentName ?? "").lowercased()

        if parent.contains("terminal") { return "Terminal shell" }
        if parent.contains("iterm") || parent == "iterm2" { return "iTerm shell" }
        if parent.contains("code helper") || parent.contains("cursor") ||
            parent.contains("windsurf") || parent == "code" {
            return "VS Code integrated terminal"
        }
        if parent == "tmux" || parent.hasPrefix("tmux:") { return "tmux session" }
        if parent == "ssh" || parent == "ssh-session" { return "SSH session" }
        if parent == "claude" { return "Claude shell" }
        if parent == "cmux" { return "cmux session" }
        if parent == "login" || parent == "launchd" { return "Login shell" }

        return "\(name) shell"
    }

    // MARK: - VS Code helper

    private static func attributeCodeHelper(_ command: String) -> String {
        let cmd = command.lowercased()

        if cmd.contains("pylance") || cmd.contains("pyright") { return "VS Code Pylance" }
        if cmd.contains("typescript-language") || cmd.contains("tsserver") { return "VS Code TypeScript server" }
        if cmd.contains("eslint") { return "VS Code ESLint server" }
        if cmd.contains("tailwind") { return "VS Code Tailwind CSS" }
        if cmd.contains("--type=extensionhost") || cmd.contains("extensionhost") { return "VS Code extension host" }
        if cmd.contains("--type=renderer") { return "VS Code renderer" }
        if cmd.contains("--type=gpu") { return "VS Code GPU process" }
        if cmd.contains("--type=plugin") { return "VS Code plugin host" }
        if cmd.contains("--type=utility") { return "VS Code utility" }

        return "VS Code helper"
    }

    // MARK: - Java

    private static func attributeJava(_ command: String) -> String {
        let cmd = command.lowercased()

        if cmd.contains("idea") || cmd.contains("intellij") { return "IntelliJ IDEA" }
        if cmd.contains("gradle") { return "Gradle build" }
        if cmd.contains("mvn") || cmd.contains("maven") { return "Maven build" }
        if cmd.contains("minecraft") { return "Minecraft" }
        if cmd.contains("elasticsearch") { return "Elasticsearch" }
        if cmd.contains("kafka") { return "Apache Kafka" }
        if cmd.contains("zookeeper") { return "Apache Zookeeper" }

        return "Java process"
    }
}
