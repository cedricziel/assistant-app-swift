import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    var isSending: Bool
    var placeholder: String
    var onSubmit: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 6)
                .disabled(isSending)
                .onSubmit { submit() }
            Button(action: submit) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.isBlank || isSending)
        }
    }

    private func submit() {
        guard !text.isBlank, !isSending else { return }
        let payload = text
        onSubmit(payload)
    }
}

#Preview {
    ChatInputBar(text: .constant(""), isSending: false, placeholder: "Message", onSubmit: { _ in })
        .padding()
}
