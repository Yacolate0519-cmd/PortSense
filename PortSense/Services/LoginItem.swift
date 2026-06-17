import Foundation
import ServiceManagement

/// Registers Port Sense as a "launch at login" item via `SMAppService`
/// (macOS 13+). Being a login item lets the app start at boot and try to claim
/// a menu-bar slot early — the same reason apps like cc-bar reliably appear.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break // already in the desired state
            }
            return true
        } catch {
            NSLog("[LoginItem] \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }
}
