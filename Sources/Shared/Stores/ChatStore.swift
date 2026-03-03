import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private var threadsByAccount: [AssistantAccount.ID: [ChatThread]] = [:]
    @Published private var pendingThreadIDs: Set<ChatThread.ID> = []

    private let chatService: ChatService

    init(chatService: ChatService = ChatService()) {
        self.chatService = chatService
    }

    func threads(for account: AssistantAccount) -> [ChatThread] {
        threadsByAccount[account.id] ?? []
    }

    func ensureDefaultThread(for account: AssistantAccount) -> ChatThread {
        if let existing = threads(for: account).first {
            return existing
        }
        let greeting = ChatMessage.system("Connected to \(account.server.displayName)")
        let thread = ChatThread(title: "New chat", messages: [greeting])
        threadsByAccount[account.id] = [thread]
        return thread
    }

    func latestThread(for account: AssistantAccount) -> ChatThread? {
        threads(for: account).first
    }

    func createThread(for account: AssistantAccount) -> ChatThread {
        let thread = ChatThread(title: "New chat")
        var threads = threads(for: account)
        threads.insert(thread, at: 0)
        threadsByAccount[account.id] = threads
        return thread
    }

    func thread(with id: ChatThread.ID, for account: AssistantAccount) -> ChatThread? {
        threads(for: account).first(where: { $0.id == id })
    }

    func isSending(threadID: ChatThread.ID) -> Bool {
        pendingThreadIDs.contains(threadID)
    }

    func send(message: String, for account: AssistantAccount) async {
        let thread = latestThread(for: account) ?? ensureDefaultThread(for: account)
        await send(message: message, in: thread.id, for: account)
    }

    func send(message: String, in threadID: ChatThread.ID, for account: AssistantAccount) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard var currentThread = thread(with: threadID, for: account) else {
            return
        }
        currentThread = currentThread.appending(ChatMessage(role: .user, content: trimmed))
        upsert(currentThread, for: account)

        pendingThreadIDs.insert(threadID)
        defer { pendingThreadIDs.remove(threadID) }

        do {
            let response = try await chatService.sendMessage(trimmed, for: account, in: currentThread)
            var refreshed = thread(with: threadID, for: account) ?? currentThread
            refreshed = refreshed.appending(response)
            upsert(refreshed, for: account)
        } catch {
            var refreshed = thread(with: threadID, for: account) ?? currentThread
            refreshed = refreshed.appending(ChatMessage.system(error.localizedDescription))
            upsert(refreshed, for: account)
        }
    }

    private func upsert(_ thread: ChatThread, for account: AssistantAccount) {
        var threads = threads(for: account)
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
        threadsByAccount[account.id] = threads
    }
}
