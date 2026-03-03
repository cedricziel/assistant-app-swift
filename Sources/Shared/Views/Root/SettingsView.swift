import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore

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
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
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
}

#Preview {
    SettingsView()
        .environmentObject(AccountStore(accounts: [PreviewData.account]))
}
