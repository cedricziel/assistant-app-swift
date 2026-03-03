import Foundation

@MainActor
final class AccountStore: ObservableObject {
    struct OpenAISubscriptionPendingAuthorization {
        let verificationURL: URL
        let userCode: String
        let instructions: String
    }

    private struct LoginRequest {
        let serverAddress: String
        let apiToken: String
        let displayName: String
        let routing: AssistantAccount.Routing
        let syncPolicy: AssistantAccount.SyncPolicy

        var requiresOpenAISubscriptionAuth: Bool {
            guard case let .directProviders(config) = routing else {
                return false
            }

            let provider: AssistantAccount.ProviderProfile? = if let defaultProviderID = config.defaultProviderID {
                config.providers.first(where: { $0.id == defaultProviderID && $0.isEnabled })
            } else {
                config.providers.first(where: { $0.isEnabled })
            }

            guard let provider else {
                return false
            }

            return provider.provider == .openAI && provider.auth == .chatGPTSubscription
        }
    }

    @Published private(set) var accounts: [AssistantAccount]
    @Published var activeAccountID: AssistantAccount.ID?
    @Published var isAuthenticating = false
    @Published var authenticationError: String?
    @Published var pendingOpenAIAuthorization: OpenAISubscriptionPendingAuthorization?

    private let authenticationService: AuthenticationService
    private let openAISubscriptionAuthService: OpenAISubscriptionAuthService
    private let accountPersistence: AccountPersistence
    private let credentialKeychain: CredentialKeychain

    init(
        accounts: [AssistantAccount]? = nil,
        authenticationService: AuthenticationService = AuthenticationService(),
        openAISubscriptionAuthService: OpenAISubscriptionAuthService = OpenAISubscriptionAuthService(),
        accountPersistence: AccountPersistence = AccountPersistence(),
        credentialKeychain: CredentialKeychain = CredentialKeychain(),
    ) {
        self.authenticationService = authenticationService
        self.openAISubscriptionAuthService = openAISubscriptionAuthService
        self.accountPersistence = accountPersistence
        self.credentialKeychain = credentialKeychain
        self.accounts = []

        if let accounts {
            self.accounts = hydrateCredentials(in: accounts)
            activeAccountID = accounts.first?.id
            return
        }

        do {
            let snapshot = try accountPersistence.load()
            self.accounts = hydrateCredentials(in: snapshot.accounts)
            if let activeID = snapshot.activeAccountID,
               snapshot.accounts.contains(where: { $0.id == activeID })
            {
                activeAccountID = activeID
            } else {
                activeAccountID = snapshot.accounts.first?.id
            }
        } catch {
            self.accounts = []
            activeAccountID = nil
        }
    }

    var activeAccount: AssistantAccount? {
        account(with: activeAccountID)
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    func account(with id: AssistantAccount.ID?) -> AssistantAccount? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    func selectAccount(_ account: AssistantAccount) {
        activeAccountID = account.id
        persistSnapshot()
    }

    func removeAccount(_ account: AssistantAccount) {
        accounts.removeAll(where: { $0.id == account.id })
        if activeAccountID == account.id {
            activeAccountID = accounts.first?.id
        }

        do {
            try credentialKeychain.removeToken(for: account.id)
        } catch {
            authenticationError = error.localizedDescription
        }

        persistSnapshot()
    }

    func login(
        serverAddress: String,
        apiToken: String,
        displayName: String,
        routing: AssistantAccount.Routing,
        syncPolicy: AssistantAccount.SyncPolicy,
    ) async {
        authenticationError = nil
        pendingOpenAIAuthorization = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let request = LoginRequest(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName,
                routing: routing,
                syncPolicy: syncPolicy,
            )
            let value = try await buildAuthenticatedAccount(
                request: request,
            )

            if let existingIndex = accounts.firstIndex(where: { matchesIdentity(of: $0, with: value.account) }) {
                let existing = accounts[existingIndex]
                try persistCredential(value.credential, for: existing.id)
                accounts[existingIndex] = AssistantAccount(
                    id: existing.id,
                    displayName: value.account.displayName,
                    userHandle: value.account.userHandle,
                    apiToken: value.account.apiToken,
                    server: value.account.server,
                    createdAt: existing.createdAt,
                    routing: value.account.routing,
                    syncPolicy: value.account.syncPolicy,
                )
                activeAccountID = existing.id
            } else {
                try persistCredential(value.credential, for: value.account.id)
                accounts.append(value.account)
                activeAccountID = value.account.id
            }

            persistSnapshot()
        } catch {
            authenticationError = error.localizedDescription
            pendingOpenAIAuthorization = nil
        }
    }

    private func persistSnapshot() {
        do {
            try accountPersistence.save(accounts: accounts, activeAccountID: activeAccountID)
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    private func matchesIdentity(of candidate: AssistantAccount, with account: AssistantAccount) -> Bool {
        candidate.routing == account.routing
            && candidate.server.baseURL == account.server.baseURL
            && candidate.userHandle == account.userHandle
    }

    private func hydrateCredentials(in accounts: [AssistantAccount]) -> [AssistantAccount] {
        accounts.map { account in
            guard account.requiresCredential else {
                return account
            }

            var hydrated = account

            do {
                if !account.apiToken.isEmpty {
                    try persistCredential(.apiKey(account.apiToken), for: account.id)
                }

                if let credential = try credential(for: account.id) {
                    hydrated.apiToken = credential.activeToken
                } else {
                    hydrated.apiToken = ""
                }
            } catch {
                authenticationError = error.localizedDescription
                hydrated.apiToken = ""
            }

            return hydrated
        }
    }

    private func buildAuthenticatedAccount(
        request: LoginRequest,
    ) async throws -> (account: AssistantAccount, credential: RemoteCredential) {
        guard request.requiresOpenAISubscriptionAuth else {
            let account = try await authenticationService.login(
                serverAddress: request.serverAddress,
                apiToken: request.apiToken,
                displayName: request.displayName,
                routing: request.routing,
                syncPolicy: request.syncPolicy,
            )
            return (account, .apiKey(account.apiToken))
        }

        let authorization = try await openAISubscriptionAuthService.beginDeviceAuthorization()
        pendingOpenAIAuthorization = OpenAISubscriptionPendingAuthorization(
            verificationURL: authorization.verificationURL,
            userCode: authorization.userCode,
            instructions: "Open ChatGPT device authorization and enter the one-time code.",
        )
        let tokens = try await openAISubscriptionAuthService.pollForTokens(authorization: authorization)
        pendingOpenAIAuthorization = nil

        let account = try await authenticationService.login(
            serverAddress: request.serverAddress,
            apiToken: tokens.accessToken,
            displayName: request.displayName,
            routing: request.routing.replacingOpenAIAccountID(with: tokens.accountID),
            syncPolicy: request.syncPolicy,
        )

        let credential = RemoteCredential.openAISubscription(
            .init(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: tokens.expiresAt,
                accountID: tokens.accountID,
            ),
        )
        return (account, credential)
    }

    private func credential(for accountID: UUID) throws -> RemoteCredential? {
        guard let data = try credentialKeychain.data(for: accountID) else {
            return nil
        }

        if let credential = try? JSONDecoder().decode(RemoteCredential.self, from: data) {
            return credential
        }

        if let token = String(data: data, encoding: .utf8) {
            return .apiKey(token)
        }

        return nil
    }

    private func persistCredential(_ credential: RemoteCredential, for accountID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        try credentialKeychain.setData(data, for: accountID)
    }
}

private extension AssistantAccount {
    var requiresCredential: Bool {
        switch routing {
        case .assistantBackend:
            true
        case let .directProviders(config):
            config.providers.contains(where: { profile in
                profile.isEnabled && profile.auth != .none
            })
        }
    }
}

extension AssistantAccount.Routing {
    func replacingOpenAIAccountID(with accountID: String?) -> Self {
        switch self {
        case let .assistantBackend(config):
            return .assistantBackend(config)
        case let .directProviders(config):
            guard let targetID = config.defaultProviderID,
                  let index = config.providers.firstIndex(where: { $0.id == targetID })
            else {
                return self
            }

            var nextConfig = config
            let provider = nextConfig.providers[index]
            guard provider.provider == .openAI else {
                return self
            }
            nextConfig.providers[index].label = accountID.map { "OpenAI (\($0))" } ?? provider.label
            return .directProviders(nextConfig)
        }
    }
}

extension AccountStore {
    func refreshOpenAISubscriptionCredentialIfNeeded(for account: AssistantAccount) async throws -> AssistantAccount {
        guard let provider = account.selectedDirectProvider,
              provider.provider == .openAI,
              provider.auth == .chatGPTSubscription
        else {
            return account
        }

        guard let credential = try credential(for: account.id),
              let subscription = credential.subscription
        else {
            return account
        }

        if subscription.expiresAt.timeIntervalSinceNow > 60 {
            return account
        }

        let refreshed = try await openAISubscriptionAuthService.refresh(refreshToken: subscription.refreshToken)
        let refreshedCredential = RemoteCredential.openAISubscription(
            .init(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: refreshed.expiresAt,
                accountID: refreshed.accountID ?? subscription.accountID,
            ),
        )
        try persistCredential(refreshedCredential, for: account.id)

        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return account
        }

        accounts[index].apiToken = refreshed.accessToken
        accounts[index].routing = accounts[index].routing.replacingOpenAIAccountID(
            with: refreshed.accountID ?? subscription.accountID,
        )
        persistSnapshot()
        return accounts[index]
    }
}
