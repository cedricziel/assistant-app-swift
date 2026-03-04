import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var shellAgentService: ShellAgentService

    @State private var agentError: String?

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
                                Text(routingDescription(for: account))
                                    .font(.caption)
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

            #if os(macOS)
            shellAgentSection
            #endif
        }
        .frame(minWidth: 360, minHeight: 240)
        .navigationTitle("Assistant Settings")
        .onAppear {
            shellAgentService.refreshStatus()
        }
        .alert(
            "Shell Agent Error",
            isPresented: Binding(
                get: { agentError != nil },
                set: { if !$0 { agentError = nil } },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let agentError {
                Text(agentError)
            }
        }
    }

    #if os(macOS)
    private var shellAgentSection: some View {
        Section("Shell Agent") {
            Toggle(
                "Shell Agent",
                isOn: Binding(
                    get: { shellAgentService.isRegistered },
                    set: { newValue in
                        do {
                            if newValue {
                                try shellAgentService.register()
                            } else {
                                try shellAgentService.unregister()
                            }
                        } catch {
                            agentError = error.localizedDescription
                            shellAgentService.refreshStatus()
                        }
                    },
                ),
            )
            .toggleStyle(.switch)

            Text(
                "Runs a background service that allows "
                    + "Assistant to execute shell commands on "
                    + "your Mac.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
    #endif

    private func storageDescription(for account: AssistantAccount) -> String {
        switch account.conversationStorage {
        case .deviceOnly:
            "Conversations stored on this device"
        case .iCloud:
            "Conversations stored in iCloud"
        }
    }

    private func routingDescription(for account: AssistantAccount) -> String {
        switch account.routing {
        case .assistantBackend:
            return "Routing: Assistant backend"
        case let .directProviders(config):
            let enabled = config.providers.filter(\.isEnabled)
            if enabled.isEmpty {
                return "Routing: Direct providers (none configured)"
            }
            let labels = enabled.map(\.label).joined(separator: ", ")
            return "Routing: Direct providers (\(labels))"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AccountStore(accounts: [PreviewData.account]))
        .environmentObject(ChatStore())
        .environmentObject(ShellAgentService())
}
