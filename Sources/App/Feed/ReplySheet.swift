import SwiftUI
import UniformTypeIdentifiers

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void

    private var accent: Color { model.post.target.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: nil, label: "Reply on \(model.post.target.displayName)", accent: accent)

            QuotedPreviewBlock(post: model.post, accent: accent)

            SheetTextEditor(text: $model.text, minHeight: 96, placeholder: "Write your reply…")

            if !model.attachments.isEmpty { AttachmentBar(attachments: $model.attachments) }

            HStack {
                Button { ImageAttaching.pick(into: $model.attachments) { model.errorMessage = $0 } } label: {
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
                canSubmit: model.canSend, onCancel: onClose,
                onSubmit: {
                    Task {
                        guard await model.send() else { return }
                        await flashSentThenClose(onClose: onClose)
                    }
                })
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            ImageAttaching.load(providers, into: $model.attachments) { model.errorMessage = $0 }
            return true
        }
        .onPasteCommand(of: [.image, .fileURL]) {
            ImageAttaching.load($0, into: $model.attachments) { model.errorMessage = $0 }
        }
        .sheetContainer()
    }
}
