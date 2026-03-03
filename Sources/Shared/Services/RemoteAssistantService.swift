import Foundation

struct RemoteAssistantService {
    enum RemoteServiceError: LocalizedError {
        case unsupportedAccount
        case invalidURL
        case httpError(Int)
        case emptyBody
        case missingMessage

        var errorDescription: String? {
            switch self {
            case .unsupportedAccount:
                return "The selected account does not support remote messaging."
            case .invalidURL:
                return "The assistant server URL is invalid."
            case let .httpError(code):
                return "Assistant server responded with status code \(code)."
            case .emptyBody:
                return "Assistant server returned an empty response."
            case .missingMessage:
                return "Assistant server response did not include a message."
            }
        }
    }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.encoder = encoder
        self.decoder = decoder
    }

    func send(
        text: String,
        account: AssistantAccount,
        conversationID: UUID
    ) async throws -> ChatMessage {
        guard account.accountType.supportsRemoteTransport else {
            throw RemoteServiceError.unsupportedAccount
        }

        let endpoint = account.server.baseURL.appendingPathComponent("message/send")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(account.apiToken)", forHTTPHeaderField: "Authorization")

        let payload = makeRequestPayload(text: text, conversationID: conversationID)
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteServiceError.emptyBody
        }
        guard 200 ..< 300 ~= http.statusCode else {
            throw RemoteServiceError.httpError(http.statusCode)
        }
        guard !data.isEmpty else {
            throw RemoteServiceError.emptyBody
        }
        let sendResponse = try decoder.decode(A2ASendMessageResponse.self, from: data)
        guard let replyText = extractReplyText(from: sendResponse) else {
            throw RemoteServiceError.missingMessage
        }
        return ChatMessage(role: .assistant, content: replyText)
    }

    private func makeRequestPayload(text: String, conversationID: UUID) -> A2ASendMessageRequest {
        let parts = [A2APart(text: text)]
        let message = A2AMessage(
            messageId: UUID().uuidString,
            contextId: conversationID.uuidString,
            taskId: nil,
            role: .user,
            parts: parts,
            metadata: nil,
            extensions: [],
            referenceTaskIds: []
        )
        var metadata: [String: A2ASendMessageRequest.MetadataValue] = [:]
        metadata["interface"] = .string("apple-app")
        metadata["platform"] = .string(ProcessInfo.processInfo.operatingSystemVersionString)
        return A2ASendMessageRequest(
            message: message,
            configuration: nil,
            metadata: metadata
        )
    }

    private func extractReplyText(from response: A2ASendMessageResponse) -> String? {
        if let message = response.message {
            return message.parts.compactMap { $0.text }.joined(separator: "\n")
        }
        if let taskMessage = response.task?.status.message {
            return taskMessage.parts.compactMap { $0.text }.joined(separator: "\n")
        }
        return nil
    }
}
