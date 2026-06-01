import SwiftUI

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void

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

            TextEditor(text: $model.text)
                .font(.body).frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button(model.isSending ? "Sending…" : "Reply") {
                    Task { await model.send(); if model.errorMessage == nil { onClose() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSend)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
