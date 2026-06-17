import Foundation

/// Spawns a system binary directly (no shell) and returns its stdout, with a
/// hard timeout. Used for `lsof` and `ps`. Mirrors the TS services which spawn
/// child processes with a 5s timeout for safety.
enum CommandRunner {
    /// Run `launchPath` with `arguments` and return stdout as a string.
    /// Returns an empty string on spawn failure or timeout.
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 5) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        // Discard stderr — lsof emits non-fatal warnings we don't care about,
        // and draining it via nullDevice avoids any pipe-buffer deadlock.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        let semaphore = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            data = stdout.fileHandleForReading.readDataToEndOfFile()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return ""
        }
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
