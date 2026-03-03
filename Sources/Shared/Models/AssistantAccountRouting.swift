import Foundation

extension AssistantAccount {
    enum Routing: Hashable, Codable {
        case assistantBackend(AssistantBackendConfig)
        case directProviders(DirectProvidersConfig)

        init(from decoder: Decoder) throws {
            let envelope = try RoutingEnvelope(from: decoder)
            switch envelope.type {
            case .assistantBackend:
                guard let config = envelope.assistantBackend else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing assistant backend config."),
                    )
                }
                self = .assistantBackend(config)
            case .directProviders:
                guard let config = envelope.directProviders else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing direct providers config."),
                    )
                }
                self = .directProviders(config)
            }
        }

        func encode(to encoder: Encoder) throws {
            let envelope = switch self {
            case let .assistantBackend(config):
                RoutingEnvelope(type: .assistantBackend, assistantBackend: config, directProviders: nil)
            case let .directProviders(config):
                RoutingEnvelope(type: .directProviders, assistantBackend: nil, directProviders: config)
            }
            try envelope.encode(to: encoder)
        }
    }

    struct AssistantBackendConfig: Hashable, Codable {
        var server: ServerEnvironment
        var credentialKind: CredentialKind
        var tenantID: String?

        init(server: ServerEnvironment, credentialKind: CredentialKind, tenantID: String? = nil) {
            self.server = server
            self.credentialKind = credentialKind
            self.tenantID = tenantID
        }
    }

    enum CredentialKind: String, Hashable, Codable {
        case apiKey
        case chatGPTSubscription
    }

    struct DirectProvidersConfig: Hashable, Codable {
        var providers: [ProviderProfile]
        var defaultProviderID: ProviderProfile.ID?

        init(providers: [ProviderProfile] = [], defaultProviderID: ProviderProfile.ID? = nil) {
            self.providers = providers
            self.defaultProviderID = defaultProviderID
        }
    }

    struct ProviderProfile: Identifiable, Hashable, Codable {
        let id: UUID
        var provider: ModelProvider
        var auth: ProviderAuth
        var label: String
        var isEnabled: Bool

        init(
            id: UUID = UUID(),
            provider: ModelProvider,
            auth: ProviderAuth,
            label: String,
            isEnabled: Bool = true,
        ) {
            self.id = id
            self.provider = provider
            self.auth = auth
            self.label = label
            self.isEnabled = isEnabled
        }
    }

    enum ModelProvider: String, Hashable, Codable {
        case openAI
        case local
    }

    enum ProviderAuth: String, Hashable, Codable {
        case none
        case apiKey
        case chatGPTSubscription
    }

    enum SyncPolicy: Hashable, Codable {
        case deviceOnly
        case iCloud(ICloudSyncConfig)

        init(from decoder: Decoder) throws {
            let envelope = try SyncPolicyEnvelope(from: decoder)
            switch envelope.type {
            case .deviceOnly:
                self = .deviceOnly
            case .iCloud:
                guard let config = envelope.iCloud else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing iCloud sync config."),
                    )
                }
                self = .iCloud(config)
            }
        }

        func encode(to encoder: Encoder) throws {
            let envelope = switch self {
            case .deviceOnly:
                SyncPolicyEnvelope(type: .deviceOnly, iCloud: nil)
            case let .iCloud(config):
                SyncPolicyEnvelope(type: .iCloud, iCloud: config)
            }
            try envelope.encode(to: encoder)
        }
    }

    struct ICloudSyncConfig: Hashable, Codable {
        var isEnabled: Bool
        var refreshIntervalSeconds: Int
        var refreshOnForeground: Bool
        var refreshOnThreadOpen: Bool

        init(
            isEnabled: Bool = true,
            refreshIntervalSeconds: Int = 60,
            refreshOnForeground: Bool = true,
            refreshOnThreadOpen: Bool = true,
        ) {
            self.isEnabled = isEnabled
            self.refreshIntervalSeconds = refreshIntervalSeconds
            self.refreshOnForeground = refreshOnForeground
            self.refreshOnThreadOpen = refreshOnThreadOpen
        }
    }
}

extension AssistantAccount {
    static func routingFromLegacy(
        accountType: AccountType,
        remoteProvider: RemoteProvider,
        remoteAuthMode: RemoteAuthMode,
        server: ServerEnvironment,
        openAIAccountID: String?,
    ) -> Routing {
        if accountType == .remote, remoteProvider == .assistantBackend {
            let credentialKind: CredentialKind = switch remoteAuthMode {
            case .apiKey:
                .apiKey
            case .chatGPTSubscription:
                .chatGPTSubscription
            }
            return .assistantBackend(
                AssistantBackendConfig(
                    server: server,
                    credentialKind: credentialKind,
                ),
            )
        }

        var providers: [ProviderProfile] = []
        if accountType == .remote, remoteProvider == .openAI {
            let auth: ProviderAuth = switch remoteAuthMode {
            case .apiKey:
                .apiKey
            case .chatGPTSubscription:
                .chatGPTSubscription
            }
            let label = openAIAccountID.map { "OpenAI (\($0))" } ?? "OpenAI"
            providers.append(
                ProviderProfile(
                    provider: .openAI,
                    auth: auth,
                    label: label,
                ),
            )
        }

        return .directProviders(
            DirectProvidersConfig(
                providers: providers,
                defaultProviderID: providers.first?.id,
            ),
        )
    }

    static func syncPolicyFromLegacy(accountType: AccountType) -> SyncPolicy {
        switch accountType {
        case .remote:
            .iCloud(ICloudSyncConfig())
        case .localDevice:
            .deviceOnly
        case .localICloud:
            .iCloud(ICloudSyncConfig())
        }
    }

    var selectedDirectProvider: ProviderProfile? {
        guard case let .directProviders(config) = routing else {
            return nil
        }

        if let defaultProviderID = config.defaultProviderID,
           let profile = config.providers.first(where: { $0.id == defaultProviderID && $0.isEnabled })
        {
            return profile
        }

        return config.providers.first(where: { $0.isEnabled })
    }

    var usesAssistantBackendRouting: Bool {
        if case .assistantBackend = routing {
            return true
        }
        return false
    }
}

private struct RoutingEnvelope: Codable {
    var type: RoutingType
    var assistantBackend: AssistantAccount.AssistantBackendConfig?
    var directProviders: AssistantAccount.DirectProvidersConfig?
}

private enum RoutingType: String, Codable {
    case assistantBackend
    case directProviders
}

private struct SyncPolicyEnvelope: Codable {
    var type: SyncPolicyType
    var iCloud: AssistantAccount.ICloudSyncConfig?
}

private enum SyncPolicyType: String, Codable {
    case deviceOnly
    case iCloud
}
