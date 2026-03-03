import Foundation

struct ChatService {
    enum ChatServiceError: LocalizedError {
        case responseMissing

        var errorDescription: String? {
            "The assistant did not return any content."
        }
    }

    private let remoteService: RemoteAssistantService

    init(remoteService: RemoteAssistantService = RemoteAssistantService()) {
        self.remoteService = remoteService
    }

    func sendMessage(
        _ content: String,
        for account: AssistantAccount,
        in thread: ChatThread
    ) async throws -> ChatMessage {
        switch account.accountType {
        case .remote:
            return try await remoteService.send(text: content, account: account, conversationID: thread.id)
        case .localDevice, .localICloud:
            // Placeholder local echo until local models are wired.
            try await Task.sleep(nanoseconds: 400_000_000)
            return ChatMessage(role: .assistant, content: "(local) \(content)")
        }
    }
}
