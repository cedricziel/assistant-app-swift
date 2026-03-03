import Foundation

struct ChatService {
    private let agentLoop: AgentLoop

    init(agentLoop: AgentLoop = AgentLoop()) {
        self.agentLoop = agentLoop
    }

    func sendMessage(
        _ content: String,
        for account: AssistantAccount,
        in thread: ChatThread,
    ) async throws -> AgentLoop.Output {
        try await agentLoop.runTurn(message: content, account: account, thread: thread)
    }
}
