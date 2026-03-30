import SwiftUI

struct RootContainerView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingSettings = false

    var body: some View {
        Group {
            if accountStore.hasAccounts {
                ChatSceneView(showSettings: $showingSettings)
            } else {
                LoginView(mode: .initial)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingSettings = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .task(id: accountStore.accounts) {
            for account in accountStore.accounts {
                _ = chatStore.ensureDefaultThread(for: account)
            }
        }
    }
}

#Preview {
    RootContainerView()
        .environmentObject(AccountStore(accounts: [PreviewData.account]))
        .environmentObject({
            let store = ChatStore()
            _ = store.ensureDefaultThread(for: PreviewData.account)
            return store
        }())
}
