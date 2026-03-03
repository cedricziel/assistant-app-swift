import Foundation

struct LocalAssistantService {
    func send(text: String, account _: AssistantAccount, conversationID _: UUID) async throws -> ChatMessage {
        try await Task.sleep(nanoseconds: 400_000_000)
        return ChatMessage(role: .assistant, content: "(local) \(text)")
    }
}
