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
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: "flag", label: "Report \(subjectLabel)", accent: accent)

            Text("Reason").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Reason", selection: $reason) {
                ForEach(ReportReason.allCases) { reason in
                    Text(reason.title).tag(reason)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text("Add context (optional)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            SheetTextEditor(text: $comment, minHeight: 60)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            SheetFooter(
                sending: isSending, sent: sent,
                successLabel: "Report sent", submitLabel: "Report", submittingLabel: "Reporting…",
                role: .destructive, canSubmit: true, onCancel: onClose, onSubmit: send)
        }
        .sheetContainer()
    }

    private func send() {
        submitSheet(isSending: $isSending, sent: $sent, errorMessage: $errorMessage,
                    onClose: onClose) {
            try await submit(reason, comment.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
