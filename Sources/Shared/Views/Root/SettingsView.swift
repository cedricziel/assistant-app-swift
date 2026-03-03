import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        Form {
            Section("Accounts") {
                if accountStore.accounts.isEmpty {
                    Text("No accounts connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountStore.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.displayName)
                                    .font(.headline)
                                Text(account.server.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(storageDescription(for: account))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                chatStore.removeData(for: account)
                                accountStore.removeAccount(account)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
        .navigationTitle("Assistant Settings")
    }

    private func storageDescription(for account: AssistantAccount) -> String {
        switch account.conversationStorage {
        case .remoteBackend:
            return "Conversations stored on remote backend"
        case .deviceOnly:
            return "Conversations stored on this device"
        case .iCloud:
            return "Conversations stored in iCloud"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AccountStore(accounts: [PreviewData.account]))
        .environmentObject(ChatStore())
}
