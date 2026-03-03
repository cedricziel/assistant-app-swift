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
                Text(account.redactedToken)
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
            return "Remote"
        case .deviceOnly:
            return "Device"
        case .iCloud:
            return "iCloud"
        }
    }
}

#Preview {
    AccountBadgeView(account: PreviewData.account)
        .padding()
}
