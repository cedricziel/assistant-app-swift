import Foundation

@MainActor
final class ApplicationSession: ObservableObject {
    let accountStore: AccountStore
    let chatStore: ChatStore

    init(accountStore: AccountStore = AccountStore(), chatStore: ChatStore = ChatStore()) {
        self.accountStore = accountStore
        self.chatStore = chatStore
    }
}
