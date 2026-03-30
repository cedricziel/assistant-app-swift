import SwiftUI

/// An inline card shown within the chat message list when the AI requests
/// permission to execute a tool (typically a shell command). Presents the
/// command, optional working directory, and prominent Approve / Deny actions.
struct ToolApprovalView: View {
    let request: ToolApprovalRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            commandSection
            actions
        }
        .padding(14)
        .background(.regularMaterial, in: cardShape)
        .overlay(cardBorder)
    }

    // MARK: - Header

    private var header: some View {
        Label {
            Text("Tool Approval Required")
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Command display

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(request.toolCall.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let command = request.command {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    )
            }

            if let workingDirectory = request.workingDirectory {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                    Text(workingDirectory)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action buttons

    private var actions: some View {
        HStack(spacing: 10) {
            Spacer()

            Button(role: .destructive, action: onDeny) {
                Label("Deny", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button(action: onApprove) {
                Label("Approve", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    // MARK: - Card shape & border

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var cardBorder: some View {
        cardShape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Simulated chat context
        MessageBubbleView(
            message: ChatMessage(
                role: .assistant,
                content: "I need to check the project structure. Let me run a command.",
            ),
        )

        ToolApprovalView(
            request: ToolApprovalRequest(
                id: "preview-1",
                toolCall: ToolCall(
                    id: "tc-1",
                    name: "bash",
                    arguments: "{\"command\":\"ls -la ~/Developer/project\",\"working_directory\":\"/Users/dev/project\"}",
                ),
                threadID: PreviewData.thread.id,
            ),
            onApprove: {},
            onDeny: {},
        )

        ToolApprovalView(
            request: ToolApprovalRequest(
                id: "preview-2",
                toolCall: ToolCall(
                    id: "tc-2",
                    name: "bash",
                    arguments: "{\"command\":\"git diff --stat HEAD~3..HEAD && echo \\\"Changes summary complete\\\"\"}",
                ),
                threadID: PreviewData.thread.id,
            ),
            onApprove: {},
            onDeny: {},
        )
    }
    .padding()
    .frame(maxWidth: 420)
}
