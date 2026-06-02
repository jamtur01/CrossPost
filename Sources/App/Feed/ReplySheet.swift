import SwiftUI

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void
    @State private var justSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reply on \(model.post.target.displayName)").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.post.authorHandle).font(.caption.bold()).foregroundStyle(.secondary)
                Text(model.post.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))

            PlainTextEditor(text: $model.text)
                .frame(minHeight: 90)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

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
