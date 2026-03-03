import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AssistantAccount]
    @Published var activeAccountID: AssistantAccount.ID?
    @Published var isAuthenticating = false
    @Published var authenticationError: String?

    private let authenticationService: AuthenticationService

    init(accounts: [AssistantAccount] = [], authenticationService: AuthenticationService = AuthenticationService()) {
        self.accounts = accounts
        self.authenticationService = authenticationService
        activeAccountID = accounts.first?.id
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
    }

    func removeAccount(_ account: AssistantAccount) {
        accounts.removeAll(where: { $0.id == account.id })
        if activeAccountID == account.id {
            activeAccountID = accounts.first?.id
        }
    }

    func login(serverAddress: String, apiToken: String, displayName: String) async {
        authenticationError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let account = try await authenticationService.login(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName
            )
            if let existingIndex = accounts.firstIndex(where: { candidate in
                candidate.server.baseURL == account.server.baseURL && candidate.userHandle == account.userHandle
            }) {
                accounts[existingIndex] = account
            } else {
                accounts.append(account)
            }
            activeAccountID = account.id
        } catch {
            authenticationError = error.localizedDescription
        }
    }
}
