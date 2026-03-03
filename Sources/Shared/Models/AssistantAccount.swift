import Foundation

struct AssistantAccount: Identifiable, Hashable, Codable {
    let id: UUID
    var displayName: String
    var userHandle: String
    var server: ServerEnvironment
    var apiToken: String
    var createdAt: Date
    var accountType: AccountType
    var remoteProvider: RemoteProvider
    var remoteAuthMode: RemoteAuthMode
    var openAIAccountID: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        userHandle: String,
        apiToken: String,
        server: ServerEnvironment,
        createdAt: Date = .now,
        accountType: AccountType = .remote,
        remoteProvider: RemoteProvider = .assistantBackend,
        remoteAuthMode: RemoteAuthMode = .apiKey,
        openAIAccountID: String? = nil,
    ) {
        self.id = id
        self.displayName = displayName
        self.userHandle = userHandle
        self.apiToken = apiToken
        self.server = server
        self.createdAt = createdAt
        self.accountType = accountType
        self.remoteProvider = remoteProvider
        self.remoteAuthMode = remoteAuthMode
        self.openAIAccountID = openAIAccountID
    }

    var redactedToken: String {
        let suffix = apiToken.suffix(4)
        return "•••\(suffix)"
    }
}

extension AssistantAccount {
    enum RemoteProvider: String, Codable {
        case assistantBackend
        case openAI
    }

    enum RemoteAuthMode: String, Codable {
        case apiKey
        case chatGPTSubscription
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
        case accountType
        case remoteProvider
        case remoteAuthMode
        case openAIAccountID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        userHandle = try container.decode(String.self, forKey: .userHandle)
        server = try container.decode(ServerEnvironment.self, forKey: .server)
        apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        accountType = try container.decodeIfPresent(AccountType.self, forKey: .accountType) ?? .remote
        remoteProvider = try container
            .decodeIfPresent(RemoteProvider.self, forKey: .remoteProvider) ?? .assistantBackend
        remoteAuthMode = try container.decodeIfPresent(RemoteAuthMode.self, forKey: .remoteAuthMode) ?? .apiKey
        openAIAccountID = try container.decodeIfPresent(String.self, forKey: .openAIAccountID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(userHandle, forKey: .userHandle)
        try container.encode(server, forKey: .server)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(accountType, forKey: .accountType)
        try container.encode(remoteProvider, forKey: .remoteProvider)
        try container.encode(remoteAuthMode, forKey: .remoteAuthMode)
        try container.encodeIfPresent(openAIAccountID, forKey: .openAIAccountID)
    }
}

extension AssistantAccount {
    enum AccountType: String, Codable {
        case remote
        case localDevice
        case localICloud

        var supportsRemoteTransport: Bool {
            self == .remote
        }

        var conversationStorage: ConversationStorage {
            switch self {
            case .remote:
                .remoteBackend
            case .localDevice:
                .deviceOnly
            case .localICloud:
                .iCloud
            }
        }
    }

    enum ConversationStorage: String, Codable {
        case remoteBackend
        case deviceOnly
        case iCloud

        var persistsLocally: Bool {
            self == .deviceOnly || self == .iCloud
        }
    }

    var conversationStorage: ConversationStorage {
        accountType.conversationStorage
    }
}

extension AssistantAccount {
    static let placeholder = AssistantAccount(
        displayName: "Primary",
        userHandle: "you",
        apiToken: "dev-token",
        server: .placeholder,
    )
}
