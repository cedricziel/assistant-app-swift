// swiftlint:disable file_length
import Foundation
import OpenAI

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
        /// All intermediate messages produced during this turn (tool calls + tool results).
        let intermediateMessages: [ChatMessage]
    }

    struct Policy {
        var maxAttempts: Int = 2
        var retryBaseDelayNanoseconds: UInt64 = 250_000_000
        /// Maximum number of tool-call round-trips per turn.
        var maxToolRoundTrips: Int = 10
    }

    enum AgentLoopError: LocalizedError {
        case exhaustedRetries
        case toolExecutionUnavailable

        var errorDescription: String? {
            switch self {
            case .exhaustedRetries:
                "The assistant could not complete the request after retrying."
            case .toolExecutionUnavailable:
                "Tool execution is not available on this platform."
            }
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

    /// Closure invoked to request user approval before executing a tool call.
    /// Returns the user's decision. If nil, tool calls are denied by default.
    typealias ToolApprovalHandler = @Sendable (ToolApprovalRequest) async -> ToolApprovalRequest.Decision

    /// Callback invoked with accumulated content as streaming tokens arrive.
    typealias StreamHandler = @Sendable (String) -> Void

    private let remoteService: RemoteAssistantService
    private let openAIService: OpenAIAssistantService
    private let localService: LocalAssistantService
    private let shellAgentService: ShellAgentService?
    private let toolApprovalHandler: ToolApprovalHandler?
    private let policy: Policy

    init(
        remoteService: RemoteAssistantService = RemoteAssistantService(),
        openAIService: OpenAIAssistantService = OpenAIAssistantService(),
        localService: LocalAssistantService = LocalAssistantService(),
        shellAgentService: ShellAgentService? = nil,
        toolApprovalHandler: ToolApprovalHandler? = nil,
        policy: Policy = Policy(),
    ) {
        self.remoteService = remoteService
        self.openAIService = openAIService
        self.localService = localService
        self.shellAgentService = shellAgentService
        self.toolApprovalHandler = toolApprovalHandler
        self.policy = policy
    }

    func runTurn(
        message: String,
        account: AssistantAccount,
        thread: ChatThread,
        onStream: StreamHandler? = nil,
    ) async throws -> Output {
        let backend = selectBackend(for: account)
        var trace: [TraceEvent] = []

        var attempt = 1
        while attempt <= policy.maxAttempts {
            trace.append(TraceEvent(
                phase: .planning,
                detail: "Selected \(backend.rawValue) backend.",
                attempt: attempt,
            ))
            trace.append(TraceEvent(phase: .generating, detail: "Generating assistant response.", attempt: attempt))

            do {
                if backend == .openAI {
                    return try await runOpenAITurn(
                        message: message,
                        account: account,
                        thread: thread,
                        trace: &trace,
                        attempt: attempt,
                        onStream: onStream,
                    )
                }
                let response = try await generate(with: backend, message: message, account: account, thread: thread)
                trace.append(TraceEvent(phase: .acting, detail: "No tool actions for this turn.", attempt: attempt))
                trace.append(TraceEvent(phase: .reflecting, detail: "Response accepted.", attempt: attempt))
                trace.append(TraceEvent(phase: .completed, detail: "Turn completed.", attempt: attempt))
                return Output(message: response, trace: trace, intermediateMessages: [])
            } catch {
                trace.append(TraceEvent(
                    phase: .reflecting,
                    detail: "Generation failed: \(error.localizedDescription)",
                    attempt: attempt,
                ))
                guard shouldRetry(error: error, backend: backend, attempt: attempt) else {
                    trace.append(TraceEvent(phase: .failed, detail: "Turn failed without retry.", attempt: attempt))
                    throw RunError.failed(underlying: error, trace: trace)
                }
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                attempt += 1
            }
        }

        trace.append(TraceEvent(phase: .failed, detail: "Retries exhausted.", attempt: policy.maxAttempts))
        throw RunError.exhausted(trace: trace)
    }

    private func runOpenAITurn(
        message: String,
        account: AssistantAccount,
        thread: ChatThread,
        trace: inout [TraceEvent],
        attempt: Int,
        onStream: StreamHandler? = nil,
    ) async throws -> Output {
        var context = ToolLoopContext(trace: trace, intermediateMessages: [], attempt: attempt, threadID: thread.id)
        let result: ChatMessage
        do {
            result = try await runOpenAIToolLoop(
                userMessage: message,
                account: account,
                thread: thread,
                context: &context,
                onStream: onStream,
            )
        } catch {
            trace = context.trace
            throw error
        }
        context.trace.append(TraceEvent(phase: .completed, detail: "Turn completed.", attempt: attempt))
        trace = context.trace
        return Output(message: result, trace: context.trace, intermediateMessages: context.intermediateMessages)
    }

    // MARK: - Backend selection

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

        if case let OpenAIAssistantService.OpenAIServiceError.httpError(statusCode, _) = error {
            return 500 ..< 600 ~= statusCode
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

// MARK: - OpenAI Tool Loop

extension AgentLoop {
    /// Context passed through the tool loop to accumulate trace and intermediate messages.
    struct ToolLoopContext {
        var trace: [TraceEvent]
        var intermediateMessages: [ChatMessage]
        let attempt: Int
        let threadID: ChatThread.ID
    }

    func runOpenAIToolLoop(
        userMessage _: String,
        account: AssistantAccount,
        thread: ChatThread,
        context: inout ToolLoopContext,
        onStream: StreamHandler? = nil,
    ) async throws -> ChatMessage {
        var conversationParams = buildConversationParams(from: thread)

        return try await executeToolRoundTrips(
            conversationParams: &conversationParams,
            account: account,
            context: &context,
            onStream: onStream,
        )
    }

    private func buildConversationParams(
        from thread: ChatThread,
    ) -> [ChatQuery.ChatCompletionMessageParam] {
        thread.messages.compactMap { msg -> ChatQuery.ChatCompletionMessageParam? in
            switch msg.role {
            case .system:
                return .system(.init(content: .textContent(msg.content)))
            case .user:
                return .user(.init(content: .string(msg.content)))
            case .assistant:
                return .assistant(.init(
                    content: .textContent(msg.content),
                    toolCalls: msg.toolCalls.map { mapToolCallParams($0) },
                ))
            case .tool:
                guard let callID = msg.toolCallID else { return nil }
                return .tool(.init(content: .textContent(msg.content), toolCallId: callID))
            }
        }
    }

    private func mapToolCallParams(
        _ calls: [ToolCall],
    ) -> [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] {
        calls.map { call in
            ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
                id: call.id,
                function: .init(arguments: call.arguments, name: call.name),
            )
        }
    }

    private func executeToolRoundTrips(
        conversationParams: inout [ChatQuery.ChatCompletionMessageParam],
        account: AssistantAccount,
        context: inout ToolLoopContext,
        onStream: StreamHandler? = nil,
    ) async throws -> ChatMessage {
        var roundTrip = 0
        while roundTrip < policy.maxToolRoundTrips {
            let result = try await openAIService.generate(
                messages: conversationParams,
                account: account,
                onStream: onStream,
            )

            guard !result.toolCalls.isEmpty else {
                context.trace.append(TraceEvent(
                    phase: .reflecting,
                    detail: "Response accepted.",
                    attempt: context.attempt,
                ))
                return result.message
            }

            context.intermediateMessages.append(result.message)
            context.trace.append(TraceEvent(
                phase: .acting,
                detail: "Executing \(result.toolCalls.count) tool call(s): \(result.toolCalls.map(\.name).joined(separator: ", ")).",
                attempt: context.attempt,
            ))

            conversationParams.append(.assistant(.init(
                content: .textContent(result.message.content),
                toolCalls: mapToolCallParams(result.toolCalls),
            )))

            await processToolCalls(result.toolCalls, conversationParams: &conversationParams, context: &context)
            roundTrip += 1
        }

        context.trace.append(TraceEvent(
            phase: .reflecting,
            detail: "Tool round-trip limit reached.",
            attempt: context.attempt,
        ))
        return ChatMessage(role: .assistant, content: "(Tool execution limit reached.)")
    }

    private func processToolCalls(
        _ toolCalls: [ToolCall],
        conversationParams: inout [ChatQuery.ChatCompletionMessageParam],
        context: inout ToolLoopContext,
    ) async {
        for toolCall in toolCalls {
            let toolResult = await approveAndExecute(toolCall, context: context)
            let toolMessage = ChatMessage.toolResult(callID: toolCall.id, output: toolResult.output)
            context.intermediateMessages.append(toolMessage)
            conversationParams.append(.tool(.init(content: .textContent(toolResult.output), toolCallId: toolCall.id)))
            context.trace.append(TraceEvent(
                phase: .acting,
                detail: "Tool \(toolCall.name) [\(toolCall.id)] \(toolResult.isError ? "failed" : "succeeded").",
                attempt: context.attempt,
            ))
        }
    }

    /// Tools that are safe to run without user approval.
    static let autoApprovedTools: Set<String> = ["datetime"]

    func approveAndExecute(_ toolCall: ToolCall, context: ToolLoopContext) async -> ToolResult {
        if Self.autoApprovedTools.contains(toolCall.name) {
            return await executeToolCall(toolCall)
        }
        guard let handler = toolApprovalHandler else {
            return ToolResult(
                toolCallID: toolCall.id,
                output: "Tool execution denied: no approval handler configured.",
                isError: true,
            )
        }
        let request = ToolApprovalRequest(id: toolCall.id, toolCall: toolCall, threadID: context.threadID)
        let decision = await handler(request)
        switch decision {
        case .approved:
            return await executeToolCall(toolCall)
        case .denied:
            return ToolResult(toolCallID: toolCall.id, output: "Tool execution denied by user.", isError: true)
        }
    }

    private func executeToolCall(_ toolCall: ToolCall) async -> ToolResult {
        switch toolCall.name {
        case "bash":
            guard let args = toolCall.bashArguments else {
                return ToolResult(toolCallID: toolCall.id, output: "Failed to decode bash arguments.", isError: true)
            }
            return await executeBashToolCall(id: toolCall.id, args: args)
        case "datetime":
            return executeDatetimeToolCall(id: toolCall.id)
        default:
            return ToolResult(toolCallID: toolCall.id, output: "Unknown tool: \(toolCall.name)", isError: true)
        }
    }

    private func executeDatetimeToolCall(id: String) -> ToolResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        formatter.locale = Locale.current
        let now = formatter.string(from: Date())
        let zone = TimeZone.current
        let output = "\(now) (\(zone.identifier), UTC\(zone.offsetDescription))"
        return ToolResult(toolCallID: id, output: output, isError: false)
    }

    private func executeBashToolCall(id: String, args: BashArguments) async -> ToolResult {
        #if os(macOS)
        guard let shellAgent = shellAgentService else {
            return ToolResult(toolCallID: id, output: "Shell agent service is not configured.", isError: true)
        }
        do {
            let result = try await shellAgent.execute(
                executablePath: "/bin/bash",
                arguments: ["-c", args.command],
                workingDirectory: args.workingDirectory,
            )
            let stdout = lossyUTF8String(from: result.standardOutput)
            let stderr = lossyUTF8String(from: result.standardError)
            let output = ToolOutputProcessing.compact(stdout: stdout, stderr: stderr, exitCode: result.exitCode)
            return ToolResult(toolCallID: id, output: output, isError: result.exitCode != 0)
        } catch {
            return ToolResult(
                toolCallID: id,
                output: "Shell execution error: \(error.localizedDescription)",
                isError: true,
            )
        }
        #else
        return ToolResult(toolCallID: id, output: "Shell execution is not available on this platform.", isError: true)
        #endif
    }

    private func lossyUTF8String(from data: Data) -> String {
        if let decoded = String(bytes: data, encoding: .utf8) {
            return decoded
        }
        let sanitizedBytes = data.map { byte in
            byte < 0x80 ? byte : UInt8(ascii: "?")
        }
        return String(bytes: sanitizedBytes, encoding: .utf8) ?? ""
    }
}

// swiftlint:enable file_length
