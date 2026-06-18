import SwiftUI

/// A custom, previewable recreation of the Sparkle "update available" window.
///
/// This is UI only. Sparkle still shows its own standard window unless it's
/// wired up via a custom `SPUUserDriver` — open the `#Preview` below in Xcode
/// to design this screen live.
struct UpdateAvailableView: View {
    let appName: String
    let currentVersion: String
    let newVersion: String
    let releaseNotes: String

    var onInstall: () -> Void = {}
    var onRemindLater: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A new version of \(appName) is available!")
                        .font(.headline)
                    Text("\(appName) \(newVersion) is now available—you have \(currentVersion). Would you like to download it now?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Release Notes")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
            ScrollView {
                Text(releaseNotes)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 160)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

            HStack {
                Button("Skip This Version", action: onSkip)
                Spacer()
                Button("Remind Me Later", action: onRemindLater)
                Button("Install Update", action: onInstall)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

#Preview {
    UpdateAvailableView(
        appName: "Port Sense",
        currentVersion: "1.0.0",
        newVersion: "1.1.0",
        releaseNotes: """
        • Float the window over full-screen apps
        • Remember window position (optional)
        • Self-updating via Sparkle
        """
    )
}
