import SwiftUI

struct RootContainerView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingAccountSheet = false

    var body: some View {
        Group {
            if accountStore.hasAccounts {
                ChatSceneView(showAccountSheet: $showingAccountSheet)
            } else {
                LoginView(mode: .initial)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingAccountSheet) {
            NavigationStack {
                LoginView(mode: .additional)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingAccountSheet = false
                            }
                        }
                    }
            }
            .presentationDetents([.fraction(0.75), .large])
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
