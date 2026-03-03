import SwiftUI

struct AccountBadgeView: View {
    let account: AssistantAccount

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.headline)
                Text(account.server.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(badgeLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var storageLabel: String {
        switch account.conversationStorage {
        case .deviceOnly:
            "Device"
        case .iCloud:
            "iCloud"
        }
    }

    private var badgeLabel: String {
        switch account.routing {
        case .assistantBackend:
            return "Assistant \(account.redactedToken)"
        case .directProviders:
            let providerName = switch account.selectedDirectProvider?.provider {
            case .openAI:
                account.selectedDirectProvider?.auth == .chatGPTSubscription ? "OpenAI Sub" : "OpenAI"
            case .local:
                "Local"
            case nil:
                "No provider"
            }
            return "\(providerName) · \(storageLabel)"
        }
    }
}

#Preview {
    AccountBadgeView(account: PreviewData.account)
        .padding()
}
