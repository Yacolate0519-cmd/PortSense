import SwiftUI

struct EmptyStateView: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
