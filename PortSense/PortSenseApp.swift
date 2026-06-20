import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine
import Sparkle

@main
struct PortSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No window scenes — this is a menu bar app. A Settings scene keeps
        // SwiftUI happy without showing anything (there's no menu to open it).
        Settings { EmptyView() }
    }
}

/// Owns the status-bar item, the panel, and a global hotkey.
///
/// Uses a real floating window (not `MenuBarExtra`/`NSPopover`, both of which
/// failed to display on a notched Mac whose menu bar was full). A global hotkey
/// (⌥⌘P) opens it regardless of whether the menu bar has room for the icon.
/// Exposes Sparkle's updater to SwiftUI (the "Check for Updates…" menu item).
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(_ updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() { updater.checkForUpdates() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ScannerStore()

    // Sparkle with our custom UI (SparkleUserDriver): background checks pop the
    // custom update window on old versions; the gear menu does a manual check.
    private let userDriver = SparkleUserDriver()
    private lazy var updater: SPUUpdater = {
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                 userDriver: userDriver, delegate: nil)
        do { try updater.start() }
        catch { NSLog("[Sparkle] startUpdater failed: \(error.localizedDescription)") }
        return updater
    }()
    private lazy var updaterModel = UpdaterViewModel(updater)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let panelSize = NSSize(width: 460, height: 540)

    private lazy var panel: NSPanel = {
        // Non-activating panel so showing/clicking it never pulls the user out of
        // another app's full-screen Space — that's what lets it overlay full screen.
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear          // let the Liquid Glass material show through
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false         // we never activate the app, so don't vanish
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // No traffic lights — dismiss like a popover (click away or ⌥⌘P).
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(store)
                .environmentObject(updaterModel)
        )
        return window
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app — shows a Dock icon you can click to open the panel.
        NSApp.setActivationPolicy(.regular)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Force-show every launch: macOS can restore a stale "hidden" state for a
        // background app's status item (e.g. after it was once dragged off the bar),
        // parking the icon off-screen even when there's room. Overriding it here
        // guarantees the icon always returns. ponytail: app must stay reachable.
        statusItem.isVisible = true
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "list.number", accessibilityDescription: "Port Sense")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Port Sense  (⌥⌘P)"
            button.action = #selector(togglePanel(_:))
            button.target = self
        }

        registerGlobalHotKey()
        registerClickOutsideToHide()
        _ = updater   // start Sparkle now so background update checks schedule

        // Enable launch-at-login once, so the app starts at boot and can try to
        // claim a menu-bar slot early (like cc-bar). User can toggle it off.
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            LoginItem.setEnabled(true)
        }

        // Open once on launch so it's visible even when the menu bar is full.
        // Delayed so activation lands after the app finishes launching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showPanel()
        }
    }

    /// Clicking the Dock icon (or reopening the app) brings the panel up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    /// Stay alive when the panel is closed — it's a background utility.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveOriginIfRemembering()
    }

    // MARK: - Panel

    @objc func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            saveOriginIfRemembering()
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // "Remember Window Position" on + a saved spot → reopen there; otherwise
        // fall back to the usual under-the-icon / top-right placement.
        if rememberPosition, let origin = savedOrigin {
            panel.setFrameOrigin(origin)
        } else {
            positionPanel()
        }
        // orderFrontRegardless (not NSApp.activate) keeps us in the current Space,
        // so the panel floats over full-screen apps instead of switching away.
        panel.orderFrontRegardless()
    }

    // MARK: - Remembered position (UserDefaults, shared with the Settings toggle)

    private var rememberPosition: Bool {
        UserDefaults.standard.bool(forKey: "rememberWindowPosition")
    }

    private var savedOrigin: NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: "windowOrigin") else { return nil }
        return NSPointFromString(s)
    }

    private func saveOriginIfRemembering() {
        guard rememberPosition else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "windowOrigin")
    }

    /// Place the panel under the menu bar icon if it's visible, otherwise pin it
    /// to the top-right of the screen.
    private func positionPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.panelSize

        var x = visible.maxX - size.width - 12
        var y = visible.maxY - size.height - 4

        if let button = statusItem.button, buttonIsOnScreen(button), let win = button.window {
            let r = win.convertToScreen(button.convert(button.bounds, to: nil))
            x = max(visible.minX + 8, min(r.midX - size.width / 2, visible.maxX - size.width - 8))
            y = r.minY - size.height - 4
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Is the status item's button actually drawn on screen (vs hidden behind
    /// the notch / clipped)? Hidden status items report bogus coordinates, so we
    /// require a sensibly positive x AND a y up in the menu bar band.
    private func buttonIsOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, let screen = NSScreen.main else { return false }
        let screenRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let inMenuBarBand = screenRect.minY > screen.frame.maxY - 40
        return screenRect.minX > 1 && screenRect.maxX <= screen.frame.maxX && inMenuBarBand
    }

    // MARK: - Click-outside-to-hide

    /// Dismiss the panel like a popover when the user clicks in another app.
    /// Global monitors only fire for events headed to *other* apps, so clicks
    /// inside our own panel (or its status-bar icon) don't trip this.
    private func registerClickOutsideToHide() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.saveOriginIfRemembering()
            self.panel.orderOut(nil)
        }
        // ponytail: monitor lives for the app's lifetime; no removal needed.
    }

    // MARK: - Global hotkey (⌥⌘P)

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: 0x50545345 /* 'PTSE' */, id: 1)
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return noErr }
                // Capture the raw pointer (Sendable); deref on the main actor.
                Task { @MainActor in
                    Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().togglePanel(nil)
                }
                return noErr
            },
            1, &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0, &hotKeyRef
        )
    }
}
