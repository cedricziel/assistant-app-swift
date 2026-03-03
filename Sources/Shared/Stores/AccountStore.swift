import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AssistantAccount]
    @Published var activeAccountID: AssistantAccount.ID?
    @Published var isAuthenticating = false
    @Published var authenticationError: String?

    private let authenticationService: AuthenticationService
    private let accountPersistence: AccountPersistence
    private let credentialKeychain: CredentialKeychain

    init(
        accounts: [AssistantAccount]? = nil,
        authenticationService: AuthenticationService = AuthenticationService(),
        accountPersistence: AccountPersistence = AccountPersistence(),
        credentialKeychain: CredentialKeychain = CredentialKeychain(),
    ) {
        self.authenticationService = authenticationService
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
            if let activeID = snapshot.activeAccountID, snapshot.accounts.contains(where: { $0.id == activeID }) {
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
        accountType: AssistantAccount.AccountType,
        remoteProvider: AssistantAccount.RemoteProvider = .assistantBackend,
    ) async {
        authenticationError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let account = try await authenticationService.login(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName,
                accountType: accountType,
                remoteProvider: remoteProvider,
            )

            if let existingIndex = accounts.firstIndex(where: { candidate in
                matchesIdentity(of: candidate, with: account)
            }) {
                let existing = accounts[existingIndex]
                if !account.apiToken.isEmpty {
                    try credentialKeychain.setToken(account.apiToken, for: existing.id)
                }

                accounts[existingIndex] = AssistantAccount(
                    id: existing.id,
                    displayName: account.displayName,
                    userHandle: account.userHandle,
                    apiToken: account.apiToken,
                    server: account.server,
                    createdAt: existing.createdAt,
                    accountType: account.accountType,
                    remoteProvider: account.remoteProvider,
                )
                activeAccountID = existing.id
            } else {
                try persistCredentialIfNeeded(for: account)
                accounts.append(account)
                activeAccountID = account.id
            }

            persistSnapshot()
        } catch {
            authenticationError = error.localizedDescription
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
        candidate.accountType == account.accountType
            && candidate.remoteProvider == account.remoteProvider
            && candidate.server.baseURL == account.server.baseURL
            && candidate.userHandle == account.userHandle
    }

    private func hydrateCredentials(in accounts: [AssistantAccount]) -> [AssistantAccount] {
        accounts.map { account in
            guard account.accountType == .remote else {
                return account
            }

            var hydrated = account

            if !account.apiToken.isEmpty {
                do {
                    try credentialKeychain.setToken(account.apiToken, for: account.id)
                } catch {
                    authenticationError = error.localizedDescription
                }
            }

            do {
                hydrated.apiToken = try credentialKeychain.token(for: account.id) ?? ""
            } catch {
                authenticationError = error.localizedDescription
                hydrated.apiToken = ""
            }

            return hydrated
        }
    }

    private func persistCredentialIfNeeded(for account: AssistantAccount) throws {
        guard account.accountType == .remote else {
            return
        }

        guard !account.apiToken.isEmpty else {
            throw AuthenticationService.AuthenticationError.missingCredentials
        }

        try credentialKeychain.setToken(account.apiToken, for: account.id)
    }
}
