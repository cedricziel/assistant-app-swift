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
                "OpenAI credentials are missing."
            case .missingMessage:
                "OpenAI did not return a message."
            }
        }
    }

    private let apiModel: Model
    private let subscriptionModel = "gpt-5.3-codex"
    private let codexEndpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    private let keychain = CredentialKeychain()
    private let authService = OpenAISubscriptionAuthService()

    init(apiModel: Model = "gpt-5-mini") {
        self.apiModel = apiModel
    }

    func send(text: String, account: AssistantAccount, conversationID _: UUID) async throws -> ChatMessage {
        guard account.accountType == .remote, account.remoteProvider == .openAI else {
            throw OpenAIServiceError.unsupportedAccount
        }

        switch account.remoteAuthMode {
        case .apiKey:
            return try await sendWithAPIKey(text: text, account: account)
        case .chatGPTSubscription:
            return try await sendWithSubscription(text: text, account: account)
        }
    }

    private func sendWithAPIKey(text: String, account: AssistantAccount) async throws -> ChatMessage {
        let apiKey = account.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIServiceError.missingCredentials
        }

        let client = OpenAI(apiToken: apiKey)
        let query = ChatQuery(
            messages: [.user(.init(content: .string(text)))],
            model: apiModel,
        )

        let result = try await client.chats(query: query)
        guard let content = result.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenAIServiceError.missingMessage
        }
        return ChatMessage(role: .assistant, content: content)
    }

    private func sendWithSubscription(text: String, account: AssistantAccount) async throws -> ChatMessage {
        let subscription = try await loadValidSubscriptionCredential(for: account)

        var request = URLRequest(url: codexEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(subscription.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("app", forHTTPHeaderField: "originator")

        if let accountID = subscription.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let body: [String: Any] = [
            "model": subscriptionModel,
            "input": [[
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": text,
                ]],
            ]],
            "store": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw OpenAIServiceError.missingMessage
        }

        guard let reply = extractResponseText(from: data) else {
            throw OpenAIServiceError.missingMessage
        }
        return ChatMessage(role: .assistant, content: reply)
    }

    private func loadValidSubscriptionCredential(
        for account: AssistantAccount,
    ) async throws -> RemoteCredential.OpenAISubscription {
        guard let data = try keychain.data(for: account.id),
              let credential = try? JSONDecoder().decode(RemoteCredential.self, from: data),
              let subscription = credential.subscription
        else {
            throw OpenAIServiceError.missingCredentials
        }

        if subscription.expiresAt.timeIntervalSinceNow > 60 {
            return subscription
        }

        let refreshed = try await authService.refresh(refreshToken: subscription.refreshToken)
        let updated = RemoteCredential.OpenAISubscription(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt,
            accountID: refreshed.accountID ?? subscription.accountID,
        )
        let payload = try JSONEncoder().encode(RemoteCredential.openAISubscription(updated))
        try keychain.setData(payload, for: account.id)
        return updated
    }

    private func extractResponseText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let text = json["output_text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content {
                    if let text = part["text"] as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        return text
                    }
                }
            }
        }

        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return content
        }

        return nil
    }
}
