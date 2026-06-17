import SwiftUI
import AppKit
import Carbon.HIToolbox

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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ScannerStore()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let panelSize = NSSize(width: 380, height: 540)

    private lazy var panel: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear          // let the Liquid Glass material show through
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // No traffic lights — dismiss like a popover (click away or ⌥⌘P).
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(store)
        )
        return window
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "list.number", accessibilityDescription: "Port Sense")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Port Sense  (⌥⌘P)"
            button.action = #selector(togglePanel(_:))
            button.target = self
        }

        registerGlobalHotKey()

        // Open once on launch so it's visible even when the menu bar is full.
        // Delayed so activation lands after the app finishes launching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showPanel()
        }
    }

    // MARK: - Panel

    @objc func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
