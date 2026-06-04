import SwiftUI

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void
    @State private var justSent = false

    private var accent: Color { model.post.target.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text("Reply on \(model.post.target.displayName)").font(.headline)
            }

            HStack(alignment: .top, spacing: 0) {
                Capsule().fill(accent.opacity(0.5)).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.post.authorHandle).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(model.post.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }
                .padding(.leading, 10)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))

            PlainTextEditor(text: $model.text)
                .frame(minHeight: 96)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Write your reply…")
                            .font(Theme.content).foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                if justSent {
                    Label("Reply sent", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel", action: onClose).disabled(justSent || model.isSending)
                Button(model.isSending ? "Sending…" : "Reply") {
                    Task {
                        await model.send()
                        guard model.errorMessage == nil else { return }
                        justSent = true
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        onClose()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSend || justSent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
