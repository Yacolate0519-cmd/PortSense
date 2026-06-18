import AppKit
import SwiftUI
import Sparkle

/// A custom Sparkle user driver: shows our SwiftUI `UpdateAvailableView` for the
/// "update found" stage instead of Sparkle's standard window, then lets Sparkle
/// do the real downloading/installing — progress is reflected back into the same
/// window via `UpdatePromptModel`.
///
/// Button mapping (what the user asked for):
///   Install Update    → reply(.install)  → downloads + installs + relaunches
///   Remind Me Later   → reply(.dismiss)  → Sparkle reminds again next check
///   Skip This Version → reply(.skip)     → not offered again until a newer one
@MainActor
final class SparkleUserDriver: NSObject, SPUUserDriver, NSWindowDelegate {
    private var window: NSWindow?
    private var model: UpdatePromptModel?
    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    // MARK: - Window

    private func present(_ model: UpdatePromptModel) {
        let window = self.window ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: UpdateAvailableView(model: model))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Software Update"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self
        return w
    }

    /// Clicking the window's close button before choosing = "Remind Me Later",
    /// so Sparkle isn't left waiting on a reply that never comes.
    func windowWillClose(_ notification: Notification) {
        if updateReply != nil { respond(.dismiss) }
    }

    private func closeWindow() { window?.orderOut(nil) }

    private func respond(_ choice: SPUUserUpdateChoice) {
        let reply = updateReply
        updateReply = nil
        reply?(choice)
    }

    private func infoAlert(_ message: String, informative: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Permission

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // The check is brief; nothing to show until we have a result.
    }

    // MARK: - Update found (custom window)

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updateReply = reply
        let model = UpdatePromptModel(
            appName: (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "App",
            currentVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "",
            newVersion: appcastItem.displayVersionString,
            releaseNotes: appcastItem.itemDescription ?? "No release notes provided."
        )
        model.onInstall = { [weak self] in
            self?.model?.phase = .downloading(fraction: nil)   // keep window, show progress
            self?.respond(.install)
        }
        model.onRemindLater = { [weak self] in self?.closeWindow(); self?.respond(.dismiss) }
        model.onSkip = { [weak self] in self?.closeWindow(); self?.respond(.skip) }
        self.model = model
        present(model)
    }

    // MARK: - Release notes (embedded in the appcast, so unused)

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    // MARK: - Download / extraction progress

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        model?.phase = .downloading(fraction: nil)
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        receivedLength = 0
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        let fraction = expectedLength > 0 ? Double(receivedLength) / Double(expectedLength) : nil
        model?.phase = .downloading(fraction: fraction)
    }
    func showDownloadDidStartExtractingUpdate() { model?.phase = .installing }
    func showExtractionReceivedProgress(_ progress: Double) { model?.phase = .installing }

    // MARK: - Install / relaunch

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        model?.phase = .installing
        reply(.install)   // auto-install and relaunch
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool,
                                          acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    // MARK: - Not found / errors

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        closeWindow()
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "the app"
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        infoAlert("You're up to date!", informative: "\(name) \(version) is the latest version available.")
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        closeWindow()
        infoAlert("Update Error", informative: error.localizedDescription)
        acknowledgement()
    }

    // MARK: - Dismiss / focus

    func dismissUpdateInstallation() { closeWindow() }
    func showUpdateInFocus() { window?.makeKeyAndOrderFront(nil) }
}
