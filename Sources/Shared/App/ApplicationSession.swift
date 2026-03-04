import Foundation

@MainActor
final class ApplicationSession: ObservableObject {
    let accountStore: AccountStore
    let chatStore: ChatStore
    let shellAgentService: ShellAgentService

    init(
        accountStore: AccountStore = AccountStore(),
        shellAgentService: ShellAgentService = ShellAgentService(),
    ) {
        self.accountStore = accountStore
        self.shellAgentService = shellAgentService

        let agentLoop = AgentLoop(shellAgentService: shellAgentService)
        let chatService = ChatService(agentLoop: agentLoop)
        chatStore = ChatStore(chatService: chatService)
    }
}
