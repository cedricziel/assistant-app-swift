import Foundation

struct AssistantAccount: Identifiable, Hashable, Codable {
    let id: UUID
    var displayName: String
    var userHandle: String
    var server: ServerEnvironment
    var apiToken: String
    var createdAt: Date
    var routing: Routing
    var syncPolicy: SyncPolicy

    init(
        id: UUID = UUID(),
        displayName: String,
        userHandle: String,
        apiToken: String,
        server: ServerEnvironment,
        createdAt: Date = .now,
        routing: Routing,
        syncPolicy: SyncPolicy,
    ) {
        self.id = id
        self.displayName = displayName
        self.userHandle = userHandle
        self.apiToken = apiToken
        self.server = server
        self.createdAt = createdAt
        self.routing = routing
        self.syncPolicy = syncPolicy
    }

    var redactedToken: String {
        let suffix = apiToken.suffix(4)
        return "•••\(suffix)"
    }
}

extension AssistantAccount {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case userHandle
        case server
        case apiToken
        case createdAt
        case routing
        case syncPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        userHandle = try container.decode(String.self, forKey: .userHandle)
        server = try container.decode(ServerEnvironment.self, forKey: .server)
        apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        routing = try container.decodeIfPresent(Routing.self, forKey: .routing) ?? .directProviders(.init())
        syncPolicy = try container.decodeIfPresent(SyncPolicy.self, forKey: .syncPolicy) ?? .deviceOnly
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(userHandle, forKey: .userHandle)
        try container.encode(server, forKey: .server)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(routing, forKey: .routing)
        try container.encode(syncPolicy, forKey: .syncPolicy)
    }
}

extension AssistantAccount {
    enum ConversationStorage: String, Codable {
        case deviceOnly
        case iCloud

        var persistsLocally: Bool {
            true
        }
    }

    var conversationStorage: ConversationStorage {
        switch syncPolicy {
        case .deviceOnly:
            .deviceOnly
        case .iCloud:
            .iCloud
        }
    }
}

extension AssistantAccount {
    static let placeholder = AssistantAccount(
        displayName: "Primary",
        userHandle: "you",
        apiToken: "dev-token",
        server: .placeholder,
        routing: .assistantBackend(
            .init(
                server: .placeholder,
                credentialKind: .apiKey,
            ),
        ),
        syncPolicy: .deviceOnly,
    )
}
