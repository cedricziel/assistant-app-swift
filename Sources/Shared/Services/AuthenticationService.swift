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
        displayName: String,
        accountType: AssistantAccount.AccountType
    ) async throws -> AssistantAccount {
        try await Task.sleep(nanoseconds: 250_000_000)

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let userHandle = normalizedDisplayName.isEmpty ? "you" : normalizedDisplayName

        switch accountType {
        case .remote:
            guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw AuthenticationError.invalidServerAddress
            }
            guard !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AuthenticationError.missingCredentials
            }
            let environment = ServerEnvironment(name: url.host ?? url.absoluteString, baseURL: url, kind: .remote)
            return AssistantAccount(
                displayName: normalizedDisplayName.isEmpty ? "Primary" : normalizedDisplayName,
                userHandle: userHandle,
                apiToken: apiToken,
                server: environment,
                accountType: .remote
            )
        case .localDevice:
            let environment = ServerEnvironment(
                name: "On this device",
                baseURL: URL(string: "assistant://local-device")!,
                kind: .localDevice
            )
            return AssistantAccount(
                displayName: normalizedDisplayName.isEmpty ? "Local" : normalizedDisplayName,
                userHandle: userHandle,
                apiToken: "",
                server: environment,
                accountType: .localDevice
            )
        case .localICloud:
            let environment = ServerEnvironment(
                name: "iCloud",
                baseURL: URL(string: "assistant://icloud")!,
                kind: .localICloud
            )
            return AssistantAccount(
                displayName: normalizedDisplayName.isEmpty ? "iCloud" : normalizedDisplayName,
                userHandle: userHandle,
                apiToken: "",
                server: environment,
                accountType: .localICloud
            )
        }
    }
}
