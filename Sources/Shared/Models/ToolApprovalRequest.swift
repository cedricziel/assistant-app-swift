import Foundation

/// Represents a pending tool call awaiting user approval.
struct ToolApprovalRequest: Identifiable {
    enum Decision {
        case approved
        case denied
    }

    let id: String
    let toolCall: ToolCall
    let threadID: ChatThread.ID

    /// The decoded command to display to the user (convenience).
    var command: String? {
        toolCall.bashArguments?.command
    }

    /// The working directory, if specified.
    var workingDirectory: String? {
        toolCall.bashArguments?.workingDirectory
    }
}
