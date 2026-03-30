import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ChatView: View {
    let account: AssistantAccount
    let thread: ChatThread

    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var toolApproval: ToolApprovalCoordinator
    @State private var composerText = ""
    @State private var isShowingTraceSheet = false

    private var isSending: Bool {
        chatStore.isSending(threadID: thread.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(thread.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if let streamingContent = chatStore.streamingContent(for: thread.id),
                           !streamingContent.isEmpty
                        {
                            MessageBubbleView(message: ChatMessage(role: .assistant, content: streamingContent))
                                .id("streaming-message")
                        }

                        if isSending, chatStore.streamingContent(for: thread.id) == nil {
                            TypingIndicatorView()
                                .id("typing-indicator")
                                .transition(.opacity)
                        }

                        if let request = pendingApprovalForThread {
                            ToolApprovalView(
                                request: request,
                                onApprove: { toolApproval.resolve(.approved) },
                                onDeny: { toolApproval.resolve(.denied) },
                            )
                            .id("tool-approval-\(request.id)")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .background(Color.chatSurfaceBackground)
                .onChange(of: thread.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isSending) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: toolApproval.pendingRequest?.id) {
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }
            Divider()
            if !traceEvents.isEmpty {
                HStack(spacing: 12) {
                    Label("\(traceEvents.count) trace events", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("View trace") {
                        isShowingTraceSheet = true
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
            ChatInputBar(
                text: $composerText,
                isSending: isSending,
                placeholder: "Message \(account.displayName)",
            ) { payload in
                send(payload)
            }
            .padding()
        }
        .navigationTitle(thread.title)
        .sheet(isPresented: $isShowingTraceSheet) {
            TraceSheetView(threadID: thread.id, isPresented: $isShowingTraceSheet)
        }
    }

    /// The pending approval request for this thread, if any.
    private var pendingApprovalForThread: ToolApprovalRequest? {
        guard let request = toolApproval.pendingRequest,
              request.threadID == thread.id
        else {
            return nil
        }
        return request
    }

    private var traceEvents: [AgentLoop.TraceEvent] {
        chatStore.latestLoopTrace(for: thread.id)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        composerText = ""
        Task {
            await chatStore.send(message: trimmed, in: thread.id, for: account)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let anchor: UnitPoint = .bottom
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                if isSending, chatStore.streamingContent(for: thread.id) != nil {
                    proxy.scrollTo("streaming-message", anchor: anchor)
                } else if isSending {
                    proxy.scrollTo("typing-indicator", anchor: anchor)
                } else if let messageID = thread.messages.last?.id {
                    proxy.scrollTo(messageID, anchor: anchor)
                }
            }
        }
    }
}

// MARK: - Trace Sheet

private struct TraceSheetView: View {
    let threadID: ChatThread.ID
    @Binding var isPresented: Bool
    @EnvironmentObject private var chatStore: ChatStore

    private var traceEvents: [AgentLoop.TraceEvent] {
        chatStore.latestLoopTrace(for: threadID)
    }

    var body: some View {
        NavigationStack {
            List(traceEvents) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.phase.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Attempt \(event.attempt)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(event.detail)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Agent Loop Trace")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        copyTraceToPasteboard()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func copyTraceToPasteboard() {
        let text = traceEvents
            .map { "[\($0.attempt)] \($0.phase.rawValue): \($0.detail)" }
            .joined(separator: "\n")
        guard !text.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Typing Indicator

private struct TypingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(0.2 * Double(index)),
                        value: isAnimating,
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.typingIndicatorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { isAnimating = true }
    }
}

private extension Color {
    static var chatSurfaceBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var typingIndicatorBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#Preview {
    ChatView(account: PreviewData.account, thread: PreviewData.thread)
        .environmentObject(ChatStore())
        .environmentObject(ToolApprovalCoordinator())
}
