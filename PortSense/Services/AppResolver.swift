import AppKit

/// Resolves a PID to the name of its owning GUI application, using macOS's own
/// knowledge of running apps. Auto-attributes most bundled apps (Control Center,
/// Spotify, Notion, …) without hand-written rules, and stays fully local.
///
/// Names are read from the bundle's **base** Info.plist (not `localizedName`),
/// so they're always English and don't follow the system language.
enum AppResolver {
    static func appName(forPID pid: Int) -> String? {
        guard pid > 0,
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return nil }

        if let url = app.bundleURL, let bundle = Bundle(url: url) {
            if let display = bundle.infoDictionary?["CFBundleDisplayName"] as? String, !display.isEmpty {
                return display
            }
            if let name = bundle.infoDictionary?["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
            // Bundle file name (e.g. "Raycast.app" → "Raycast") is also non-localized.
            let base = url.deletingPathExtension().lastPathComponent
            if !base.isEmpty { return base }
        }

        // Last resort — may follow the system language.
        return app.localizedName
    }
}
