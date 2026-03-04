import Foundation

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
        case tool
    }

    let id: UUID
    var role: Role
    var content: String
    var timestamp: Date

    /// Tool calls requested by the assistant (non-nil when the assistant invokes tools).
    var toolCalls: [ToolCall]?

    /// The tool call ID this message is responding to (set when role == .tool).
    var toolCallID: String?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = .now,
        toolCalls: [ToolCall]? = nil,
        toolCallID: String? = nil,
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    var isFromCurrentUser: Bool {
        role == .user
    }

    /// Whether this assistant message contains pending tool calls.
    var hasToolCalls: Bool {
        guard role == .assistant, let calls = toolCalls else { return false }
        return !calls.isEmpty
    }
}

extension ChatMessage {
    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, content: text)
    }

    /// Create a tool-result message to submit back to the LLM.
    static func toolResult(callID: String, output: String) -> ChatMessage {
        ChatMessage(role: .tool, content: output, toolCallID: callID)
    }
}
