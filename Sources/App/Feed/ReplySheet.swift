import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void

    @State private var attachmentPreparation = AttachmentPreparationOwner()

    private var accent: Color { model.post.target.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(
                icon: nil,
                label: "Reply on \(model.post.target.displayName)",
                accent: accent
            )

            QuotedPreviewBlock(post: model.post, accent: accent)

            SheetTextEditor(text: $model.text, minHeight: 96, placeholder: "Write your reply…")

            if !model.attachments.isEmpty { AttachmentBar(attachments: $model.attachments) }

            HStack {
                Button(action: chooseFiles) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.attachments.count >= TargetLimits.imageMax)
                .help(model.attachments.count >= TargetLimits.imageMax
                      ? "Maximum \(TargetLimits.imageMax) images"
                      : "Add image")

                if model.post.target == .mastodon {
                    VisibilityMenu(visibility: $model.visibility, accent: accent)
                }

                Spacer()

                Text("\(model.count)/\(model.limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(counterColor(count: model.count, limit: model.limit))
            }

            if let issues = model.blockedIssues, !issues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(validationMessage(issue) { _ in "Reply" })
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            SheetFooter(
                sending: model.isSending, sent: model.didPost,
                successLabel: "Reply sent", submitLabel: "Reply", submittingLabel: "Sending…",
                canSubmit: model.canSend,
                onCancel: close,
                onSubmit: {
                    Task {
                        guard await model.send() else { return }
                        await flashSentThenClose(onClose: close)
                    }
                })
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            prepare(providers)
            return true
        }
        .onPasteCommand(of: [.image, .fileURL], perform: prepare)
        .onDisappear {
            attachmentPreparation.cancel()
        }
        .sheetContainer()
    }

    private func chooseFiles() {
        guard let selection = ImageAttaching.selectFiles(
            remainingSlots: TargetLimits.imageMax - model.attachments.count
        ) else {
            return
        }
        attachmentPreparation.start(
            operation: { await ImageAttaching.prepare(selection) },
            onPrepared: model.applyPreparedAttachments
        )
    }

    private func prepare(_ providers: [NSItemProvider]) {
        let selection = ImageAttaching.selectProviders(
            providers,
            remainingSlots: TargetLimits.imageMax - model.attachments.count
        )
        attachmentPreparation.start(
            operation: { await ImageAttaching.prepare(selection) },
            onPrepared: model.applyPreparedAttachments
        )
    }

    private func close() {
        attachmentPreparation.cancel()
        onClose()
    }
}
