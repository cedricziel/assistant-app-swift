import Foundation

/// A tool call requested by the LLM.
struct ToolCall: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let arguments: String

    /// Decoded arguments for the bash tool.
    var bashArguments: BashArguments? {
        guard name == "bash" else { return nil }
        let data = Data(arguments.utf8)
        return try? JSONDecoder().decode(BashArguments.self, from: data)
    }
}

/// Decoded arguments for a `bash` tool invocation.
struct BashArguments: Codable, Hashable {
    let command: String
    let workingDirectory: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case workingDirectory = "working_directory"
    }
}

/// Result of executing a tool call, ready to submit back to the LLM.
struct ToolResult: Codable, Hashable {
    let toolCallID: String
    let output: String
    let isError: Bool
}
