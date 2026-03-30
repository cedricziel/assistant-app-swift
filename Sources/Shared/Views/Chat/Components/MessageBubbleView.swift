import AssistantShared
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
        .contextMenu {
            Button {
                copyContent()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
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
            } else if message.role == .tool {
                Text("Tool Result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if message.hasToolCalls {
                Text("Tool Call")
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

    private func copyContent() {
        guard !message.content.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = message.content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .assistant:
            Color.assistantBubbleBackground
        case .system:
            Color.systemBubbleBackground
        case .user:
            Color.accentColor
        case .tool:
            Color.toolBubbleBackground
        }
    }
}

private extension Color {
    static var assistantBubbleBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var systemBubbleBackground: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var toolBubbleBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGray6)
        #elseif os(macOS)
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}

#Preview {
    VStack {
        MessageBubbleView(message: ChatMessage(role: .assistant, content: "Sure, let's get started."))
        MessageBubbleView(message: ChatMessage(role: .user, content: "Draft a plan for me."))
    }
    .padding()
}
