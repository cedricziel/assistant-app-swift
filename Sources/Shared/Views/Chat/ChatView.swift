import SwiftUI

struct ChatView: View {
    let account: AssistantAccount
    let thread: ChatThread

    @EnvironmentObject private var chatStore: ChatStore
    @State private var composerText = ""
    @State private var isShowingTrace = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(thread.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                .onChange(of: thread.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }
            Divider()
            if !traceEvents.isEmpty {
                DisclosureGroup("Agent loop trace", isExpanded: $isShowingTrace) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(traceEvents) { event in
                            Text("[\(event.attempt)] \(event.phase.rawValue): \(event.detail)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
            ChatInputBar(
                text: $composerText,
                isSending: chatStore.isSending(threadID: thread.id),
                placeholder: "Message \(account.displayName)"
            ) { payload in
                send(payload)
            }
            .padding()
        }
        .navigationTitle(thread.title)
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
        guard let messageID = thread.messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(messageID, anchor: .bottom)
            }
        }
    }
}

#Preview {
    ChatView(account: PreviewData.account, thread: PreviewData.thread)
        .environmentObject(ChatStore())
}
