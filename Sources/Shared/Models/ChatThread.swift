import Foundation

struct ChatThread: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var lastMessage: ChatMessage? {
        messages.last
    }
}

extension ChatThread {
    func appending(_ message: ChatMessage) -> ChatThread {
        var next = self
        next.messages.append(message)
        next.updatedAt = message.timestamp
        if title == "New chat" && message.role == .user {
            next.title = String(message.content.prefix(32)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return next
    }
}
