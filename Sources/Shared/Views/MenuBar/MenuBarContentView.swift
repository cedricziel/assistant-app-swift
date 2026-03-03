import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var quickReplyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let account = accountStore.activeAccount,
               let thread = chatStore.latestThread(for: account)
            {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.headline)
                    Text(account.server.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(thread.messages.suffix(10)) { message in
                            MessageBubbleView(message: message)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 220)

                ChatInputBar(
                    text: $quickReplyText,
                    isSending: chatStore.isSending(threadID: thread.id),
                    placeholder: "Quick reply"
                ) { text in
                    quickReplyText = ""
                    Task {
                        await chatStore.send(message: text, in: thread.id, for: account)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Open Assistant",
                    systemImage: "message",
                    description: Text("Use the main window to connect an account before chatting from the menu bar.")
                )
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(AccountStore(accounts: [PreviewData.account]))
        .environmentObject({
            let store = ChatStore()
            store.ensureDefaultThread(for: PreviewData.account)
            return store
        }())
}
