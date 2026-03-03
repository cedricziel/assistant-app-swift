import Foundation

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    var content: String
    var timestamp: Date

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    var isFromCurrentUser: Bool {
        role == .user
    }
}

extension ChatMessage {
    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, content: text)
    }
}
