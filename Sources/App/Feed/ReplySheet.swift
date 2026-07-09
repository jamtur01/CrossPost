import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void
    @State private var justSent = false

    private var accent: Color { model.post.target.accent }
    private var counterColor: Color {
        if model.count > model.limit { return .red }
        if model.count >= model.limit - 20 { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: nil, label: "Reply on \(model.post.target.displayName)", accent: accent)

            QuotedPreviewBlock(post: model.post, accent: accent)

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
                    .foregroundStyle(counterColor)
            }

            if let issues = model.blockedIssues, !issues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(validationMessage(issue))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            SheetFooter(
                sending: model.isSending, sent: justSent,
                successLabel: "Reply sent", submitLabel: "Reply", submittingLabel: "Sending…",
                canSubmit: model.canSend, onCancel: onClose,
                onSubmit: {
                    Task {
                        guard await model.send() else { return }
                        justSent = true
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        onClose()
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

    private func validationMessage(_ issue: ValidationIssue) -> String {
        switch issue {
        case .empty:
            return "Reply is empty."
        case .tooLong(_, let target, let count, let limit):
            return "Reply is too long for \(target.displayName): \(count)/\(limit)."
        case .tooLongBytes(_, let target, let count, let limit):
            return "Reply is too long for \(target.displayName): \(count)/\(limit) bytes."
        case .tooManyImages(_, let target, let count, let limit):
            return "Reply has too many images for \(target.displayName): \(count)/\(limit)."
        case .altTextTooLong(_, let imageIndex, let target, let count, let limit):
            return "Reply image \(imageIndex + 1) alt text is too long for "
                + "\(target.displayName): \(count)/\(limit)."
        }
    }
}
