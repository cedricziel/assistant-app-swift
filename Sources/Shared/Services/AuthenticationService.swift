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
        routing: AssistantAccount.Routing,
        syncPolicy: AssistantAccount.SyncPolicy,
    ) async throws -> AssistantAccount {
        try await Task.sleep(nanoseconds: 250_000_000)

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let userHandle = normalizedDisplayName.isEmpty ? "you" : normalizedDisplayName

        switch routing {
        case let .assistantBackend(config):
            let environment = try assistantBackendEnvironment(
                explicitServer: config.server,
                serverAddress: serverAddress,
            )
            guard !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AuthenticationError.missingCredentials
            }

            return AssistantAccount(
                displayName: normalizedDisplayName.isEmpty ? "Primary" : normalizedDisplayName,
                userHandle: userHandle,
                apiToken: apiToken,
                server: environment,
                accountType: .remote,
                remoteProvider: .assistantBackend,
                remoteAuthMode: config.credentialKind == .chatGPTSubscription ? .chatGPTSubscription : .apiKey,
                routing: .assistantBackend(
                    .init(
                        server: environment,
                        credentialKind: config.credentialKind,
                        tenantID: config.tenantID,
                    ),
                ),
                syncPolicy: syncPolicy,
            )
        case let .directProviders(config):
            return makeDirectProviderAccount(
                normalizedDisplayName: normalizedDisplayName,
                userHandle: userHandle,
                apiToken: apiToken,
                syncPolicy: syncPolicy,
                config: config,
            )
        }
    }

    private func assistantBackendEnvironment(
        explicitServer: ServerEnvironment,
        serverAddress: String,
    ) throws -> ServerEnvironment {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            if explicitServer.baseURL.absoluteString.isEmpty {
                throw AuthenticationError.invalidServerAddress
            }
            return explicitServer
        }
        return ServerEnvironment(name: url.host ?? url.absoluteString, baseURL: url, kind: .remote)
    }

    private func makeDirectProviderAccount(
        normalizedDisplayName: String,
        userHandle: String,
        apiToken: String,
        syncPolicy: AssistantAccount.SyncPolicy,
        config: AssistantAccount.DirectProvidersConfig,
    ) -> AssistantAccount {
        let fallbackDisplay = normalizedDisplayName.isEmpty ? "Direct" : normalizedDisplayName
        let kind: ServerEnvironment.Kind = switch syncPolicy {
        case .deviceOnly:
            .localDevice
        case .iCloud:
            .localICloud
        }

        let descriptor = switch kind {
        case .localDevice:
            LocalAccountDescriptor(
                name: "Direct providers",
                fallbackDisplay: "Direct",
                url: "assistant://direct-providers",
            )
        case .localICloud:
            LocalAccountDescriptor(
                name: "Direct providers",
                fallbackDisplay: "Direct",
                url: "assistant://direct-providers-icloud",
            )
        case .remote:
            LocalAccountDescriptor(
                name: "Direct providers",
                fallbackDisplay: "Direct",
                url: "assistant://direct-providers",
            )
        }

        let primary = primaryProvider(in: config)
        let legacyProvider: AssistantAccount.RemoteProvider = if primary?.provider == .openAI {
            .openAI
        } else {
            .assistantBackend
        }
        let legacyAuth: AssistantAccount.RemoteAuthMode = if primary?.auth == .chatGPTSubscription {
            .chatGPTSubscription
        } else {
            .apiKey
        }

        return AssistantAccount(
            displayName: fallbackDisplay.isEmpty ? descriptor.fallbackDisplay : fallbackDisplay,
            userHandle: userHandle,
            apiToken: apiToken,
            server: ServerEnvironment(name: descriptor.name, baseURL: URL(string: descriptor.url)!, kind: kind),
            accountType: kind == .localICloud ? .localICloud : .localDevice,
            remoteProvider: legacyProvider,
            remoteAuthMode: legacyAuth,
            routing: .directProviders(config),
            syncPolicy: syncPolicy,
        )
    }

    private func primaryProvider(in config: AssistantAccount.DirectProvidersConfig) -> AssistantAccount
        .ProviderProfile?
    {
        if let defaultProviderID = config.defaultProviderID,
           let profile = config.providers.first(where: { $0.id == defaultProviderID && $0.isEnabled })
        {
            return profile
        }
        return config.providers.first(where: { $0.isEnabled })
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
