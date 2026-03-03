import SwiftUI

struct ChatSceneView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var showAccountSheet: Bool

    @State private var selectedThreadID: ChatThread.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedThreadID) {
                Section("Accounts") {
                    ForEach(accountStore.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.displayName)
                                    .font(.headline)
                                Text(account.server.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if accountStore.activeAccountID == account.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            accountStore.selectAccount(account)
                            selectDefaultThread()
                        }
                    }
                    Button {
                        showAccountSheet = true
                    } label: {
                        Label("Add account", systemImage: "plus")
                    }
                }

                if let account = accountStore.activeAccount {
                    Section("Conversations") {
                        ForEach(chatStore.threads(for: account)) { thread in
                            Label(thread.title, systemImage: "bubble.left")
                                .tag(thread.id)
                        }
                        Button {
                            let thread = chatStore.createThread(for: account)
                            selectedThreadID = thread.id
                        } label: {
                            Label("New conversation", systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            .navigationTitle("Assistant")
            .listStyle(.sidebar)
        } detail: {
            if let account = accountStore.activeAccount,
               let threadID = selectedThreadID,
               let thread = chatStore.thread(with: threadID, for: account)
            {
                ChatView(account: account, thread: thread)
            } else if accountStore.activeAccount != nil {
                ContentUnavailableView(
                    "Choose a conversation",
                    systemImage: "ellipsis.bubble",
                    description: Text("Select or start a thread from the list."),
                )
            } else {
                ContentUnavailableView("Connect an account", systemImage: "person.crop.circle.badge.plus")
            }
        }
        .onAppear(perform: selectDefaultThread)
        .onChange(of: accountStore.activeAccountID) {
            selectDefaultThread()
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAccountSheet = true
                } label: {
                    Label("Manage accounts", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
        #endif
    }

    private func selectDefaultThread() {
        guard let account = accountStore.activeAccount else {
            selectedThreadID = nil
            return
        }
        chatStore.loadThreadsIfNeeded(for: account)
        if let first = chatStore.threads(for: account).first {
            selectedThreadID = first.id
        } else {
            let thread = chatStore.ensureDefaultThread(for: account)
            selectedThreadID = thread.id
        }
    }
}

#Preview {
    ChatSceneView(showAccountSheet: .constant(false))
        .environmentObject({
            let store = AccountStore(accounts: [PreviewData.account])
            store.activeAccountID = PreviewData.account.id
            return store
        }())
        .environmentObject({
            let store = ChatStore()
            _ = store.ensureDefaultThread(for: PreviewData.account)
            return store
        }())
}
