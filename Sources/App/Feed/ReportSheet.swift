import SwiftUI

/// Reports a post or account for moderation: pick a reason, add an optional
/// note, submit. The caller supplies the platform call via `submit`.
struct ReportSheet: View {
    let subjectLabel: String
    var accent: Color = .accentColor
    let submit: (ReportReason, String) async throws -> Void
    let onClose: () -> Void

    @State private var reason: ReportReason = .spam
    @State private var comment = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flag").foregroundStyle(accent)
                Text("Report \(subjectLabel)").font(Theme.columnTitle)
            }

            Text("Reason").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Reason", selection: $reason) {
                ForEach(ReportReason.allCases) { reason in
                    Text(reason.title).tag(reason)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text("Add context (optional)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            PlainTextEditor(text: $comment)
                .frame(minHeight: 60)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                if sent {
                    Label("Report sent", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .disabled(sending || sent)
                Button(sending ? "Reporting…" : "Report", role: .destructive) { send() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(sending || sent)
            }
        }
        .padding(20)
        .frame(width: Theme.sheetWidth)
    }

    private func send() {
        sending = true
        errorMessage = nil
        Task {
            defer { sending = false }
            do {
                try await submit(reason, comment.trimmingCharacters(in: .whitespacesAndNewlines))
                sent = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                onClose()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}
