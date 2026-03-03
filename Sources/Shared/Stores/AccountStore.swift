import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AssistantAccount]
    @Published var activeAccountID: AssistantAccount.ID?
    @Published var isAuthenticating = false
    @Published var authenticationError: String?

    private let authenticationService: AuthenticationService
    private let accountPersistence: AccountPersistence

    init(
        accounts: [AssistantAccount]? = nil,
        authenticationService: AuthenticationService = AuthenticationService(),
        accountPersistence: AccountPersistence = AccountPersistence()
    ) {
        self.authenticationService = authenticationService
        self.accountPersistence = accountPersistence

        if let accounts {
            self.accounts = accounts
            activeAccountID = accounts.first?.id
            return
        }

        do {
            let snapshot = try accountPersistence.load()
            self.accounts = snapshot.accounts
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
        persistSnapshot()
    }

    func login(
        serverAddress: String,
        apiToken: String,
        displayName: String,
        accountType: AssistantAccount.AccountType
    ) async {
        authenticationError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let account = try await authenticationService.login(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName,
                accountType: accountType
            )
            if let existingIndex = accounts.firstIndex(where: { candidate in
                matchesIdentity(of: candidate, with: account)
            }) {
                let existing = accounts[existingIndex]
                accounts[existingIndex] = AssistantAccount(
                    id: existing.id,
                    displayName: account.displayName,
                    userHandle: account.userHandle,
                    apiToken: account.apiToken,
                    server: account.server,
                    createdAt: existing.createdAt,
                    accountType: account.accountType
                )
                activeAccountID = existing.id
            } else {
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
            && candidate.server.baseURL == account.server.baseURL
            && candidate.userHandle == account.userHandle
    }
}
