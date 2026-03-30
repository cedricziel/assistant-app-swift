import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var shellAgentService: ShellAgentService

    @State private var agentError: String?
    @State private var accountPendingRemoval: AssistantAccount?
    @State private var showingAddAccount = false

    var body: some View {
        List {
            Section("Accounts") {
                if accountStore.accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add an account to start a conversation."),
                    )
                } else {
                    ForEach(accountStore.accounts) { account in
                        accountRow(for: account)
                    }
                }

                Button {
                    showingAddAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
            }

            #if os(macOS)
            shellAgentSection
            #endif
        }
        .navigationTitle("Settings")
        #if os(iOS)
            .listStyle(.insetGrouped)
        #else
            .listStyle(.inset)
        #endif
            .frame(minWidth: 480, minHeight: 360)
            .onAppear {
                shellAgentService.refreshStatus()
            }
            .sheet(isPresented: $showingAddAccount) {
                NavigationStack {
                    LoginView(mode: .additional)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    showingAddAccount = false
                                }
                            }
                        }
                }
                .presentationDetents([.fraction(0.85), .large])
            }
            .confirmationDialog(
                "Remove Account?",
                isPresented: Binding(
                    get: { accountPendingRemoval != nil },
                    set: { isPresented in
                        if !isPresented {
                            accountPendingRemoval = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: accountPendingRemoval,
            ) { account in
                Button("Remove \(account.displayName)", role: .destructive) {
                    removeAccount(account)
                }
                Button("Cancel", role: .cancel) {}
            } message: { account in
                Text("\(account.displayName) and its local conversations will be removed from this device.")
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

    private func accountRow(for account: AssistantAccount) -> some View {
        Button {
            accountStore.selectAccount(account)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
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
                if accountStore.activeAccountID == account.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Active account")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                accountPendingRemoval = account
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button("Remove Account", role: .destructive) {
                accountPendingRemoval = account
            }
        }
    }

    private func removeAccount(_ account: AssistantAccount) {
        chatStore.removeData(for: account)
        accountStore.removeAccount(account)
        accountPendingRemoval = nil
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

            Text("Runs a background service that lets Assistant execute shell commands on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            shellAgentStatusView
        }
    }

    @ViewBuilder
    private var shellAgentStatusView: some View {
        switch shellAgentService.agentStatus {
        case .enabled:
            Label("Enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .notRegistered:
            Label("Disabled", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 4) {
                Label("Requires Approval", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Text("Open System Settings > General > Login Items and enable the agent for this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") {
                    openLoginItemsSettings()
                }
                .font(.caption)
            }
        case .notFound:
            Label(
                "Agent not found in app bundle. Try a clean build.",
                systemImage: "xmark.circle",
            )
            .foregroundStyle(.red)
            .font(.callout)
        case .unknown:
            EmptyView()
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
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
