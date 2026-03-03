import Foundation

struct AssistantAccount: Identifiable, Hashable, Codable {
    let id: UUID
    var displayName: String
    var userHandle: String
    var server: ServerEnvironment
    var apiToken: String
    var createdAt: Date
    var accountType: AccountType

    init(
        id: UUID = UUID(),
        displayName: String,
        userHandle: String,
        apiToken: String,
        server: ServerEnvironment,
        createdAt: Date = .now,
        accountType: AccountType = .remote
    ) {
        self.id = id
        self.displayName = displayName
        self.userHandle = userHandle
        self.apiToken = apiToken
        self.server = server
        self.createdAt = createdAt
        self.accountType = accountType
    }

    var redactedToken: String {
        let suffix = apiToken.suffix(4)
        return "•••\(suffix)"
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
    }
}

extension AssistantAccount {
    static let placeholder = AssistantAccount(
        displayName: "Primary",
        userHandle: "you",
        apiToken: "dev-token",
        server: .placeholder
    )
}
