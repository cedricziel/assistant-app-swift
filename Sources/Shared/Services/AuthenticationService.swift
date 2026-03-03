import Foundation

struct AuthenticationService {
    private struct LocalAccountDescriptor {
        let name: String
        let fallbackDisplay: String
        let url: String
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

        return AssistantAccount(
            displayName: fallbackDisplay.isEmpty ? descriptor.fallbackDisplay : fallbackDisplay,
            userHandle: userHandle,
            apiToken: apiToken,
            server: ServerEnvironment(name: descriptor.name, baseURL: URL(string: descriptor.url)!, kind: kind),
            routing: .directProviders(config),
            syncPolicy: syncPolicy,
        )
    }
}
