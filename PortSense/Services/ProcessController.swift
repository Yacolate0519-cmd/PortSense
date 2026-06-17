import Foundation
import Darwin

/// Result of attempting to release/kill a process.
enum ReleaseResult: Sendable {
    case ok
    /// Graceful SIGTERM didn't stop it — needs an explicit force quit.
    case needsForce
    case failed(String)
}

/// Terminates a process by PID. Sends SIGTERM first and only escalates to
/// SIGKILL when `force` is requested. Ported from the `port:release` handler.
enum ProcessController {
    /// Does the process exist? `kill(pid, 0)` succeeds if it exists and we may
    /// signal it; EPERM means it exists but we lack permission; ESRCH means gone.
    private static func processExists(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    static func release(pid: Int32, force: Bool) -> ReleaseResult {
        guard pid > 0 else { return .failed("Invalid PID") }

        // Already gone — treat as success.
        if !processExists(pid) { return .ok }

        let signal = force ? SIGKILL : SIGTERM
        if kill(pid, signal) != 0 {
            if errno == ESRCH { return .ok } // raced; it's gone
            return .failed(String(cString: strerror(errno)))
        }

        if force { return .ok }

        // Wait up to 1500ms checking if the process died.
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            usleep(100_000) // 100ms
            if !processExists(pid) { return .ok }
        }

        // Still alive after the graceful signal.
        return .needsForce
    }
}
