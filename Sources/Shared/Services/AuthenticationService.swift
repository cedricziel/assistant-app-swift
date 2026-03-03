import Foundation

struct AuthenticationService {
    enum AuthenticationError: LocalizedError {
        case invalidServerAddress
        case missingCredentials

        var errorDescription: String? {
            switch self {
            case .invalidServerAddress:
                return "The server URL looks invalid."
            case .missingCredentials:
                return "An API token is required to authenticate."
            }
        }
    }

    func login(
        serverAddress: String,
        apiToken: String,
        displayName: String
    ) async throws -> AssistantAccount {
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AuthenticationError.invalidServerAddress
        }
        guard !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthenticationError.missingCredentials
        }

        try await Task.sleep(nanoseconds: 250_000_000)

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let userHandle = normalizedDisplayName.isEmpty ? "you" : normalizedDisplayName
        let environment = ServerEnvironment(name: url.host ?? url.absoluteString, baseURL: url)
        return AssistantAccount(
            displayName: normalizedDisplayName.isEmpty ? "Primary" : normalizedDisplayName,
            userHandle: userHandle,
            apiToken: apiToken,
            server: environment
        )
    }
}
