import Foundation
import Testing

struct AgentLoopToolTests {
    // MARK: - Datetime tool execution

    @Test func datetimeToolReturnsCurrentDate() async {
        let loop = AgentLoop()
        let toolCall = ToolCall(id: "call-1", name: "datetime", arguments: "{}")

        // Execute through the tool loop by creating a minimal context.
        // Since datetime is auto-approved, it should execute without an approval handler.
        let result = await executeTool(toolCall, using: loop)

        #expect(!result.isError)
        #expect(!result.output.isEmpty)
        // Output should contain a year (e.g. "2026")
        #expect(result.output.contains("202"))
        // Output should contain timezone identifier
        #expect(result.output.contains(TimeZone.current.identifier))
    }

    @Test func datetimeToolIncludesUTCOffset() async {
        let loop = AgentLoop()
        let toolCall = ToolCall(id: "call-2", name: "datetime", arguments: "{}")
        let result = await executeTool(toolCall, using: loop)

        #expect(result.output.contains("UTC"))
    }

    // MARK: - Auto-approval

    @Test func datetimeToolDoesNotRequireApproval() async {
        // Create a loop with NO approval handler.
        // Datetime should still execute because it's auto-approved.
        let loop = AgentLoop(toolApprovalHandler: nil)
        let toolCall = ToolCall(id: "call-3", name: "datetime", arguments: "{}")
        let result = await executeTool(toolCall, using: loop)

        #expect(!result.isError, "datetime should auto-approve without a handler")
    }

    @Test func bashToolDeniedWithoutApprovalHandler() async {
        // Create a loop with NO approval handler.
        // Bash should be denied because it requires approval.
        let loop = AgentLoop(toolApprovalHandler: nil)
        let toolCall = ToolCall(id: "call-4", name: "bash", arguments: "{\"command\":\"echo hello\"}")
        let result = await executeTool(toolCall, using: loop)

        #expect(result.isError, "bash should be denied without an approval handler")
        #expect(result.output.contains("denied"))
    }

    @Test func unknownToolDeniedWithoutApprovalHandler() async {
        // Unknown tools are not auto-approved, so without a handler they are denied.
        let loop = AgentLoop(toolApprovalHandler: nil)
        let toolCall = ToolCall(id: "call-5", name: "unknown_tool", arguments: "{}")
        let result = await executeTool(toolCall, using: loop)

        #expect(result.isError)
        #expect(result.output.contains("denied"))
    }

    @Test func unknownToolReturnsErrorWhenApproved() async {
        // With an approval handler that auto-approves, unknown tools hit the dispatch
        // and return an "Unknown tool" error.
        let loop = AgentLoop(toolApprovalHandler: { _ in .approved })
        let toolCall = ToolCall(id: "call-6", name: "unknown_tool", arguments: "{}")
        let result = await executeTool(toolCall, using: loop)

        #expect(result.isError)
        #expect(result.output.contains("Unknown tool"))
    }

    // MARK: - ToolCall model

    @Test func bashArgumentsDecodedCorrectly() {
        let call = ToolCall(
            id: "c1",
            name: "bash",
            arguments: "{\"command\":\"ls -la\",\"working_directory\":\"/tmp\"}",
        )
        let args = call.bashArguments
        #expect(args?.command == "ls -la")
        #expect(args?.workingDirectory == "/tmp")
    }

    @Test func bashArgumentsWithoutWorkingDirectory() {
        let call = ToolCall(id: "c2", name: "bash", arguments: "{\"command\":\"date\"}")
        let args = call.bashArguments
        #expect(args?.command == "date")
        #expect(args?.workingDirectory == nil)
    }

    @Test func bashArgumentsNilForNonBashTool() {
        let call = ToolCall(id: "c3", name: "datetime", arguments: "{}")
        #expect(call.bashArguments == nil)
    }

    @Test func bashArgumentsNilForInvalidJSON() {
        let call = ToolCall(id: "c4", name: "bash", arguments: "not json")
        #expect(call.bashArguments == nil)
    }

    // MARK: - Helper

    /// Exercises the internal approveAndExecute → executeToolCall path.
    /// Uses a ToolLoopContext with a dummy thread ID.
    private func executeTool(_ toolCall: ToolCall, using loop: AgentLoop) async -> ToolResult {
        // We need to call the internal method indirectly. Since approveAndExecute
        // and executeToolCall are private, we'll use processToolCalls via a
        // minimal OpenAI tool loop context. However, these are private methods.
        //
        // Instead, build a minimal scenario: create an AgentLoop and use its
        // internal tool processing by going through the public interface
        // indirectly. For unit testing private methods we use @testable import
        // and call them via a test helper extension.
        //
        // Since the methods take inout ToolLoopContext, let's test at the
        // integration level by checking behavior through the public API.
        //
        // For now, use a direct call if accessible via @testable.
        let context = AgentLoop.ToolLoopContext(
            trace: [],
            intermediateMessages: [],
            attempt: 1,
            threadID: UUID(),
        )
        return await loop.approveAndExecute(toolCall, context: context)
    }
}
