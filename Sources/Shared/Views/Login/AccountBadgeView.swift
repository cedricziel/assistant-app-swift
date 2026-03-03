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
            if account.accountType == .remote {
                Text(remoteBadgeLabel)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(storageLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var storageLabel: String {
        switch account.conversationStorage {
        case .remoteBackend:
            "Remote"
        case .deviceOnly:
            "Device"
        case .iCloud:
            "iCloud"
        }
    }

    private var remoteBadgeLabel: String {
        let providerName = switch account.remoteProvider {
        case .assistantBackend:
            "Assistant"
        case .openAI:
            "OpenAI"
        }
        return "\(providerName) \(account.redactedToken)"
    }
}

#Preview {
    AccountBadgeView(account: PreviewData.account)
        .padding()
}
