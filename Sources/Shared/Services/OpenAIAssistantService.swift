import Foundation
import OpenAI

struct OpenAIAssistantService {
    enum OpenAIServiceError: LocalizedError {
        case unsupportedAccount
        case missingCredentials
        case missingMessage

        var errorDescription: String? {
            switch self {
            case .unsupportedAccount:
                "The selected account does not support OpenAI messaging."
            case .missingCredentials:
                "An OpenAI API key is required to send messages."
            case .missingMessage:
                "OpenAI did not return a message."
            }
        }
    }

    private let model: Model

    init(model: Model = "gpt-5-mini") {
        self.model = model
    }

    func send(text: String, account: AssistantAccount, conversationID _: UUID) async throws -> ChatMessage {
        guard account.accountType == .remote, account.remoteProvider == .openAI else {
            throw OpenAIServiceError.unsupportedAccount
        }

        let apiKey = account.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIServiceError.missingCredentials
        }

        let client = OpenAI(apiToken: apiKey)
        let query = ChatQuery(
            messages: [.user(.init(content: .string(text)))],
            model: model,
        )

        let result = try await client.chats(query: query)
        guard let content = result.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenAIServiceError.missingMessage
        }

        return ChatMessage(role: .assistant, content: content)
    }
}
