import Foundation

struct AuthenticationService {
    private struct LocalAccountDescriptor {
        let name: String
        let fallbackDisplay: String
        let url: String
    }

    private struct RemoteConfiguration {
        let provider: AssistantAccount.RemoteProvider
        let authMode: AssistantAccount.RemoteAuthMode
        let accountID: String?
    }

    enum AuthenticationError: LocalizedError {
        case invalidServerAddress
        case missingCredentials

        var errorDescription: String? {
            switch self {
            case .invalidServerAddress:
                "The server URL looks invalid."
            case .missingCredentials:
                "An API token is required to authenticate."
            }
        }
    }

    func login(
        serverAddress: String,
        apiToken: String,
        displayName: String,
        accountType: AssistantAccount.AccountType,
        remoteProvider: AssistantAccount.RemoteProvider = .assistantBackend,
        remoteAuthMode: AssistantAccount.RemoteAuthMode = .apiKey,
        openAIAccountID: String? = nil,
    ) async throws -> AssistantAccount {
        try await Task.sleep(nanoseconds: 250_000_000)

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let userHandle = normalizedDisplayName.isEmpty ? "you" : normalizedDisplayName

        switch accountType {
        case .remote:
            let configuration = RemoteConfiguration(
                provider: remoteProvider,
                authMode: remoteAuthMode,
                accountID: openAIAccountID,
            )
            return try makeRemoteAccount(
                serverAddress: serverAddress,
                apiToken: apiToken,
                normalizedDisplayName: normalizedDisplayName,
                userHandle: userHandle,
                configuration: configuration,
            )

        case .localDevice:
            return makeLocalAccount(
                normalizedDisplayName: normalizedDisplayName,
                userHandle: userHandle,
                kind: .localDevice,
            )

        case .localICloud:
            return makeLocalAccount(
                normalizedDisplayName: normalizedDisplayName,
                userHandle: userHandle,
                kind: .localICloud,
            )
        }
    }

    private func makeRemoteAccount(
        serverAddress: String,
        apiToken: String,
        normalizedDisplayName: String,
        userHandle: String,
        configuration: RemoteConfiguration,
    ) throws -> AssistantAccount {
        guard !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthenticationError.missingCredentials
        }

        let environment: ServerEnvironment
        switch configuration.provider {
        case .assistantBackend:
            guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw AuthenticationError.invalidServerAddress
            }
            environment = ServerEnvironment(name: url.host ?? url.absoluteString, baseURL: url, kind: .remote)
        case .openAI:
            environment = ServerEnvironment(
                name: "OpenAI",
                baseURL: URL(string: "https://api.openai.com/v1")!,
                kind: .remote,
            )
        }

        return AssistantAccount(
            displayName: normalizedDisplayName.isEmpty ? "Primary" : normalizedDisplayName,
            userHandle: userHandle,
            apiToken: apiToken,
            server: environment,
            accountType: .remote,
            remoteProvider: configuration.provider,
            remoteAuthMode: configuration.authMode,
            openAIAccountID: configuration.accountID,
        )
    }

    private func makeLocalAccount(
        normalizedDisplayName: String,
        userHandle: String,
        kind: ServerEnvironment.Kind,
    ) -> AssistantAccount {
        let descriptor = switch kind {
        case .localDevice:
            LocalAccountDescriptor(name: "On this device", fallbackDisplay: "Local", url: "assistant://local-device")
        case .localICloud:
            LocalAccountDescriptor(name: "iCloud", fallbackDisplay: "iCloud", url: "assistant://icloud")
        case .remote:
            LocalAccountDescriptor(name: "Remote", fallbackDisplay: "Remote", url: "assistant://remote")
        }

        let accountType: AssistantAccount.AccountType = switch kind {
        case .localDevice:
            .localDevice
        case .localICloud:
            .localICloud
        case .remote:
            .remote
        }

        return AssistantAccount(
            displayName: normalizedDisplayName.isEmpty ? descriptor.fallbackDisplay : normalizedDisplayName,
            userHandle: userHandle,
            apiToken: "",
            server: ServerEnvironment(name: descriptor.name, baseURL: URL(string: descriptor.url)!, kind: kind),
            accountType: accountType,
        )
    }
}
