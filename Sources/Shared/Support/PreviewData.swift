import Foundation

enum PreviewData {
    static let server = ServerEnvironment(name: "Preview", baseURL: URL(string: "https://preview.assistant")!)
    static let account = AssistantAccount(
        displayName: "Preview",
        userHandle: "previewer",
        apiToken: "preview-token",
        server: server
    )
    static let thread: ChatThread = {
        let intro = ChatMessage.system("Preview bootstrap ready")
        let user = ChatMessage(role: .user, content: "How do I talk to the assistant?")
        let assistant = ChatMessage(role: .assistant, content: "Just start typing and the backend will answer once wired up.")
        return ChatThread(title: "Preview Conversation", messages: [intro, user, assistant])
    }()
}
