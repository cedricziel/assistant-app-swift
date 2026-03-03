import MarkdownUI
import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isFromCurrentUser {
                Spacer(minLength: 40)
                bubble
                    .tint(.accentColor)
                    .foregroundStyle(.white)
            } else {
                bubble
                    .foregroundStyle(.primary)
                Spacer(minLength: 40)
            }
        }
        .transition(.move(edge: message.isFromCurrentUser ? .trailing : .leading).combined(with: .opacity))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .system {
                Text("System")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Markdown(message.content)
                .font(.body)
        }
        .padding(12)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .assistant:
            return Color(red: 0.93, green: 0.95, blue: 0.99)
        case .system:
            return Color(red: 0.85, green: 0.87, blue: 0.92)
        case .user:
            return Color.accentColor
        }
    }
}

#Preview {
    VStack {
        MessageBubbleView(message: ChatMessage(role: .assistant, content: "Sure, let's get started."))
        MessageBubbleView(message: ChatMessage(role: .user, content: "Draft a plan for me."))
    }
    .padding()
}
