import SwiftUI

@main
struct PortSenseApp: App {
    @StateObject private var store = ScannerStore()

    var body: some Scene {
        MenuBarExtra("Port Sense", systemImage: "powerplug.fill") {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
