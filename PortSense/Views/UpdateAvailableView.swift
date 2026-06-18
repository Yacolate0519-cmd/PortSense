import SwiftUI

/// Drives the custom update window. The Sparkle user driver
/// (`SparkleUserDriver`) mutates `phase` as the update downloads and installs;
/// the buttons call back into it. Open the `#Preview` below to design it live.
@MainActor
final class UpdatePromptModel: ObservableObject {
    enum Phase: Equatable {
        case available
        case downloading(fraction: Double?)   // nil → indeterminate
        case installing
    }

    let appName: String
    let currentVersion: String
    let newVersion: String
    let releaseNotes: String
    @Published var phase: Phase = .available

    var onInstall: () -> Void = {}
    var onRemindLater: () -> Void = {}
    var onSkip: () -> Void = {}

    init(appName: String, currentVersion: String, newVersion: String, releaseNotes: String) {
        self.appName = appName
        self.currentVersion = currentVersion
        self.newVersion = newVersion
        self.releaseNotes = releaseNotes
    }
}

struct UpdateAvailableView: View {
    @ObservedObject var model: UpdatePromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A new version of \(model.appName) is available!")
                        .font(.headline)
                    Text("\(model.appName) \(model.newVersion) is now available—you have \(model.currentVersion). Would you like to install it?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Release Notes")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.releaseNotes)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 160)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

            footer
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .available:
            HStack {
                Button("Skip This Version", action: model.onSkip)
                Spacer()
                Button("Remind Me Later", action: model.onRemindLater)
                Button("Install Update", action: model.onInstall)
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading(let fraction):
            HStack(spacing: 10) {
                if let fraction {
                    ProgressView(value: fraction).frame(maxWidth: .infinity)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text("Downloading…").font(.callout).foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    UpdateAvailableView(model: UpdatePromptModel(
        appName: "Port Sense",
        currentVersion: "1.0.0",
        newVersion: "1.1.0",
        releaseNotes: """
        • Float the window over full-screen apps
        • Remember window position (optional)
        • Self-updating via Sparkle
        • Hello This is Test Version
        """
    ))
}
