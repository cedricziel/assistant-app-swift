import Foundation

struct RemoteCredential: Codable {
    enum Kind: String, Codable {
        case apiKey
        case openAISubscription
    }

    struct OpenAISubscription: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var accountID: String?
    }

    var kind: Kind
    var apiKey: String?
    var openAISubscription: OpenAISubscription?

    static func apiKey(_ token: String) -> RemoteCredential {
        RemoteCredential(
            kind: .apiKey,
            apiKey: token,
            openAISubscription: nil,
        )
    }

    static func openAISubscription(_ value: OpenAISubscription) -> RemoteCredential {
        RemoteCredential(
            kind: .openAISubscription,
            apiKey: nil,
            openAISubscription: value,
        )
    }

    var activeToken: String {
        switch kind {
        case .apiKey:
            apiKey ?? ""
        case .openAISubscription:
            openAISubscription?.accessToken ?? ""
        }
    }

    var subscription: OpenAISubscription? {
        guard kind == .openAISubscription else {
            return nil
        }
        return openAISubscription
    }
}
