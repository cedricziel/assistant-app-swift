import Foundation

struct ChatService {
    enum ChatServiceError: LocalizedError {
        case notImplemented

        var errorDescription: String? {
            "Chat streaming has not been wired up to the backend yet."
        }
    }

    func sendMessage(
        _ content: String,
        for account: AssistantAccount,
        in thread: ChatThread
    ) async throws -> ChatMessage {
        // This is a placeholder that mimics assistant latency and echoes the request.
        try await Task.sleep(nanoseconds: 800_000_000)
        let echo = "(\(account.server.displayName)) \(content)"
        return ChatMessage(role: .assistant, content: "Echo: \(echo)")
    }
}
