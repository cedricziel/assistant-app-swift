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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(thread.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
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
                .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                .onChange(of: thread.messages.count) {
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
                isSending: chatStore.isSending(threadID: thread.id),
                placeholder: "Message \(account.displayName)",
            ) { payload in
                send(payload)
            }
            .padding()
        }
        .navigationTitle(thread.title)
        .sheet(isPresented: $isShowingTraceSheet) {
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
                            isShowingTraceSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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

    private var traceText: String {
        traceEvents
            .map { event in
                "[\(event.attempt)] \(event.phase.rawValue): \(event.detail)"
            }
            .joined(separator: "\n")
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

    private func copyTraceToPasteboard() {
        guard !traceText.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = traceText
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(traceText, forType: .string)
        #endif
    }
}

#Preview {
    ChatView(account: PreviewData.account, thread: PreviewData.thread)
        .environmentObject(ChatStore())
        .environmentObject(ToolApprovalCoordinator())
}
