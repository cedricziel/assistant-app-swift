import Foundation

struct AgentLoop {
    enum Phase: String {
        case planning
        case generating
        case acting
        case reflecting
        case completed
        case failed
    }

    enum Backend: String {
        case local
        case remote
        case openAI
    }

    struct TraceEvent: Identifiable {
        let id: UUID
        let phase: Phase
        let detail: String
        let attempt: Int
        let timestamp: Date

        init(phase: Phase, detail: String, attempt: Int, timestamp: Date = .now) {
            id = UUID()
            self.phase = phase
            self.detail = detail
            self.attempt = attempt
            self.timestamp = timestamp
        }
    }

    struct Output {
        let message: ChatMessage
        let trace: [TraceEvent]
    }

    struct Policy {
        var maxAttempts: Int = 2
        var retryBaseDelayNanoseconds: UInt64 = 250_000_000
    }

    enum AgentLoopError: LocalizedError {
        case exhaustedRetries

        var errorDescription: String? {
            "The assistant could not complete the request after retrying."
        }
    }

    enum RunError: LocalizedError {
        case failed(underlying: Error, trace: [TraceEvent])
        case exhausted(trace: [TraceEvent])

        var trace: [TraceEvent] {
            switch self {
            case let .failed(_, trace):
                trace
            case let .exhausted(trace):
                trace
            }
        }

        var errorDescription: String? {
            switch self {
            case let .failed(underlying, _):
                underlying.localizedDescription
            case .exhausted:
                AgentLoopError.exhaustedRetries.localizedDescription
            }
        }
    }

    private let remoteService: RemoteAssistantService
    private let openAIService: OpenAIAssistantService
    private let localService: LocalAssistantService
    private let policy: Policy

    init(
        remoteService: RemoteAssistantService = RemoteAssistantService(),
        openAIService: OpenAIAssistantService = OpenAIAssistantService(),
        localService: LocalAssistantService = LocalAssistantService(),
        policy: Policy = Policy(),
    ) {
        self.remoteService = remoteService
        self.openAIService = openAIService
        self.localService = localService
        self.policy = policy
    }

    func runTurn(message: String, account: AssistantAccount, thread: ChatThread) async throws -> Output {
        let backend = selectBackend(for: account)
        var trace: [TraceEvent] = []

        var attempt = 1
        while attempt <= policy.maxAttempts {
            trace.append(TraceEvent(
                phase: .planning,
                detail: "Selected \(backend.rawValue) backend.",
                attempt: attempt,
            ))

            do {
                trace.append(TraceEvent(phase: .generating, detail: "Generating assistant response.", attempt: attempt))
                let response = try await generate(with: backend, message: message, account: account, thread: thread)

                trace.append(TraceEvent(phase: .acting, detail: "No tool actions for this turn.", attempt: attempt))
                trace.append(TraceEvent(phase: .reflecting, detail: "Response accepted.", attempt: attempt))
                trace.append(TraceEvent(phase: .completed, detail: "Turn completed.", attempt: attempt))
                return Output(message: response, trace: trace)
            } catch {
                trace.append(
                    TraceEvent(
                        phase: .reflecting,
                        detail: "Generation failed: \(error.localizedDescription)",
                        attempt: attempt,
                    ),
                )

                guard shouldRetry(error: error, backend: backend, attempt: attempt) else {
                    trace.append(TraceEvent(phase: .failed, detail: "Turn failed without retry.", attempt: attempt))
                    throw RunError.failed(underlying: error, trace: trace)
                }

                let delay = retryDelayNanoseconds(for: attempt)
                try await Task.sleep(nanoseconds: delay)
                attempt += 1
            }
        }

        trace.append(TraceEvent(phase: .failed, detail: "Retries exhausted.", attempt: policy.maxAttempts))
        throw RunError.exhausted(trace: trace)
    }

    private func selectBackend(for account: AssistantAccount) -> Backend {
        switch account.routing {
        case .assistantBackend:
            return .remote
        case .directProviders:
            guard let provider = account.selectedDirectProvider else {
                return .local
            }
            switch provider.provider {
            case .openAI:
                return .openAI
            case .local:
                return .local
            }
        }
    }

    private func generate(
        with backend: Backend,
        message: String,
        account: AssistantAccount,
        thread: ChatThread,
    ) async throws -> ChatMessage {
        switch backend {
        case .remote:
            try await remoteService.send(text: message, account: account, conversationID: thread.id)
        case .openAI:
            try await openAIService.send(text: message, account: account, conversationID: thread.id)
        case .local:
            try await localService.send(text: message, account: account, conversationID: thread.id)
        }
    }

    private func shouldRetry(error: Error, backend: Backend, attempt: Int) -> Bool {
        guard backend == .remote || backend == .openAI else { return false }
        guard attempt < policy.maxAttempts else { return false }

        if error is URLError {
            return true
        }

        guard let remoteError = error as? RemoteAssistantService.RemoteServiceError else {
            return false
        }

        if case let .httpError(statusCode) = remoteError {
            return 500 ..< 600 ~= statusCode
        }

        return false
    }

    private func retryDelayNanoseconds(for attempt: Int) -> UInt64 {
        guard attempt > 0 else { return policy.retryBaseDelayNanoseconds }
        let exponent = UInt64(max(0, attempt - 1))
        let multiplier = UInt64(1) << exponent
        return policy.retryBaseDelayNanoseconds * multiplier
    }
}
