import Foundation

@MainActor
final class ApplicationSession: ObservableObject {
    let accountStore: AccountStore
    let chatStore: ChatStore
    let shellAgentService: ShellAgentService
    let toolApprovalCoordinator: ToolApprovalCoordinator

    init(
        accountStore: AccountStore = AccountStore(),
        shellAgentService: ShellAgentService = ShellAgentService(),
        toolApprovalCoordinator: ToolApprovalCoordinator = ToolApprovalCoordinator(),
    ) {
        self.accountStore = accountStore
        self.shellAgentService = shellAgentService
        self.toolApprovalCoordinator = toolApprovalCoordinator

        let coordinator = toolApprovalCoordinator
        let approvalHandler: AgentLoop.ToolApprovalHandler = { request in
            await coordinator.requestApproval(for: request)
        }

        let agentLoop = AgentLoop(
            shellAgentService: shellAgentService,
            toolApprovalHandler: approvalHandler,
        )
        let chatService = ChatService(agentLoop: agentLoop)
        chatStore = ChatStore(chatService: chatService)
    }
}
