import Foundation
import OpenAI

struct OpenAIAssistantService {
    enum OpenAIServiceError: LocalizedError {
        case unsupportedAccount
        case missingCredentials
        case emptyChoices(model: String)
        case httpError(statusCode: Int, body: String)
        case unparsableResponse(body: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedAccount:
                "The selected account does not support OpenAI messaging."
            case .missingCredentials:
                "OpenAI credentials are missing."
            case let .emptyChoices(model):
                "OpenAI returned no choices for model \(model)."
            case let .httpError(statusCode, body):
                "OpenAI returned HTTP \(statusCode): \(body)"
            case let .unparsableResponse(body):
                "Could not extract message from response: \(body)"
            }
        }
    }

    /// Response from a single generation call. May contain text, tool calls, or both.
    struct GenerationResult {
        let message: ChatMessage
        let toolCalls: [ToolCall]
    }

    private let apiModel: Model
    private let subscriptionModel = "gpt-5.3-codex"
    private let codexEndpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    private let keychain = CredentialKeychain()
    private let authService = OpenAISubscriptionAuthService()

    /// Bash tool definition passed to the Chat Completions API.
    static let bashToolParam: ChatQuery.ChatCompletionToolParam = {
        let schema = JSONSchema(
            .type(.object),
            .properties([
                "command": JSONSchema(
                    .type(.string),
                    .description("The shell command to execute."),
                ),
                "working_directory": JSONSchema(
                    .type(.string),
                    .description("Optional working directory for the command."),
                ),
            ]),
            .required(["command"]),
            .additionalProperties(.boolean(false)),
        )

        return ChatQuery.ChatCompletionToolParam(
            function: .init(
                name: "bash",
                description: "Execute a shell command on the user's machine and return stdout, stderr, and exit code.",
                parameters: schema,
                strict: true,
            ),
        )
    }()

    init(apiModel: Model = "gpt-5-mini") {
        self.apiModel = apiModel
    }

    // MARK: - Public API

    func send(text: String, account: AssistantAccount, conversationID _: UUID) async throws -> ChatMessage {
        let result = try await generate(
            messages: [.user(.init(content: .string(text)))],
            account: account,
        )
        return result.message
    }

    /// Generate a response with full conversation history and tool support.
    func generate(
        messages: [ChatQuery.ChatCompletionMessageParam],
        account: AssistantAccount,
    ) async throws -> GenerationResult {
        guard let provider = account.selectedDirectProvider,
              provider.provider == .openAI
        else {
            throw OpenAIServiceError.unsupportedAccount
        }

        switch provider.auth {
        case .apiKey:
            return try await generateWithAPIKey(messages: messages, account: account)
        case .chatGPTSubscription:
            // Subscription path doesn't support tool calling yet.
            let text = messages.compactMap { param -> String? in
                if case let .user(msg) = param, case let .string(text) = msg.content { return text }
                return nil
            }.last ?? ""
            let msg = try await sendWithSubscription(text: text, account: account)
            return GenerationResult(message: msg, toolCalls: [])
        case .none:
            throw OpenAIServiceError.missingCredentials
        }
    }

    /// Submit tool results back to the model and get the next response.
    func submitToolResults(
        conversationMessages: [ChatQuery.ChatCompletionMessageParam],
        account: AssistantAccount,
    ) async throws -> GenerationResult {
        try await generate(messages: conversationMessages, account: account)
    }

    // MARK: - Private

    private func generateWithAPIKey(
        messages: [ChatQuery.ChatCompletionMessageParam],
        account: AssistantAccount,
    ) async throws -> GenerationResult {
        let apiKey = account.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIServiceError.missingCredentials
        }

        let client = OpenAI(apiToken: apiKey)
        let query = ChatQuery(
            messages: messages,
            model: apiModel,
            tools: [Self.bashToolParam],
        )

        let result = try await client.chats(query: query)
        guard let choice = result.choices.first else {
            throw OpenAIServiceError.emptyChoices(model: apiModel)
        }

        let content = choice.message.content ?? ""
        let toolCalls: [ToolCall] = (choice.message.toolCalls ?? []).map { chatToolCall in
            ToolCall(id: chatToolCall.id, name: chatToolCall.function.name, arguments: chatToolCall.function.arguments)
        }

        let message = ChatMessage(
            role: .assistant,
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
        )
        return GenerationResult(message: message, toolCalls: toolCalls)
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
            "instructions": "You are a helpful assistant.",
            "input": [[
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": text,
                ]],
            ]],
            "stream": true,
            "store": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw OpenAIServiceError.httpError(statusCode: statusCode, body: String(errorBody.prefix(300)))
        }

        let reply = try await collectSSEText(from: bytes)
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIServiceError.unparsableResponse(body: "(empty stream)")
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

    /// Reads an SSE byte stream and accumulates output text deltas.
    private func collectSSEText(
        from bytes: URLSession.AsyncBytes,
    ) async throws -> String {
        var result = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }
            if type == "response.output_text.delta",
               let delta = json["delta"] as? String
            {
                result += delta
            }
        }
        return result
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

    /// Truncated preview of response body for error diagnostics.
    private func responsePreview(_ data: Data) -> String {
        let raw = String(data: data.prefix(300), encoding: .utf8) ?? "(binary)"
        return raw.count < data.count ? raw + "..." : raw
    }
}
