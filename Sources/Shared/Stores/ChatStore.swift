import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private var threadsByAccount: [AssistantAccount.ID: [ChatThread]] = [:]
    @Published private var pendingThreadIDs: Set<ChatThread.ID> = []
    @Published private var loopTraceByThreadID: [ChatThread.ID: [AgentLoop.TraceEvent]] = [:]
    @Published var persistenceError: String?

    private let chatService: ChatService
    private let threadPersistence: ChatThreadPersisting
    private var hydratedAccountIDs: Set<AssistantAccount.ID> = []

    init(
        chatService: ChatService = ChatService(),
        threadPersistence: ChatThreadPersisting = ChatThreadPersistence(),
    ) {
        self.chatService = chatService
        self.threadPersistence = threadPersistence
    }

    func threads(for account: AssistantAccount) -> [ChatThread] {
        threadsByAccount[account.id] ?? []
    }

    func loadThreadsIfNeeded(for account: AssistantAccount) {
        hydrateThreadsIfNeeded(for: account)
    }

    func ensureDefaultThread(for account: AssistantAccount) -> ChatThread {
        hydrateThreadsIfNeeded(for: account)
        if let existing = threads(for: account).first {
            return existing
        }
        let greeting = ChatMessage.system("Connected to \(account.server.displayName)")
        let thread = ChatThread(title: "New chat", messages: [greeting])
        threadsByAccount[account.id] = [thread]
        persistThreads(for: account)
        return thread
    }

    func latestThread(for account: AssistantAccount) -> ChatThread? {
        threads(for: account).first
    }

    func createThread(for account: AssistantAccount) -> ChatThread {
        hydrateThreadsIfNeeded(for: account)
        let thread = ChatThread(title: "New chat")
        var threads = threads(for: account)
        threads.insert(thread, at: 0)
        threadsByAccount[account.id] = threads
        persistThreads(for: account)
        return thread
    }

    func thread(with id: ChatThread.ID, for account: AssistantAccount) -> ChatThread? {
        threads(for: account).first(where: { $0.id == id })
    }

    func isSending(threadID: ChatThread.ID) -> Bool {
        pendingThreadIDs.contains(threadID)
    }

    func latestLoopTrace(for threadID: ChatThread.ID) -> [AgentLoop.TraceEvent] {
        loopTraceByThreadID[threadID] ?? []
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
            let output = try await chatService.sendMessage(trimmed, for: account, in: currentThread)
            var refreshed = thread(with: threadID, for: account) ?? currentThread
            for intermediate in output.intermediateMessages {
                refreshed = refreshed.appending(intermediate)
            }
            refreshed = refreshed.appending(output.message)
            upsert(refreshed, for: account)
            loopTraceByThreadID[threadID] = output.trace
        } catch {
            var refreshed = thread(with: threadID, for: account) ?? currentThread
            refreshed = refreshed.appending(ChatMessage.system(error.localizedDescription))
            upsert(refreshed, for: account)
            if let runError = error as? AgentLoop.RunError {
                loopTraceByThreadID[threadID] = runError.trace
            }
        }
    }

    private func upsert(_ thread: ChatThread, for account: AssistantAccount) {
        hydrateThreadsIfNeeded(for: account)
        var threads = threads(for: account)
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
        threadsByAccount[account.id] = threads
        persistThreads(for: account)
    }

    func removeData(for account: AssistantAccount) {
        let threadIDs = Set((threadsByAccount[account.id] ?? []).map(\.id))
        for threadID in threadIDs {
            loopTraceByThreadID[threadID] = nil
        }
        threadsByAccount[account.id] = nil
        hydratedAccountIDs.remove(account.id)
        do {
            try threadPersistence.removeThreads(for: account)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func hydrateThreadsIfNeeded(for account: AssistantAccount) {
        guard !hydratedAccountIDs.contains(account.id) else { return }
        hydratedAccountIDs.insert(account.id)
        do {
            threadsByAccount[account.id] = try threadPersistence.loadThreads(for: account)
            persistenceError = nil
        } catch {
            threadsByAccount[account.id] = []
            persistenceError = error.localizedDescription
        }
    }

    private func persistThreads(for account: AssistantAccount) {
        guard account.conversationStorage.persistsLocally else { return }
        let threads = threadsByAccount[account.id] ?? []
        do {
            try threadPersistence.saveThreads(threads, for: account)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}
