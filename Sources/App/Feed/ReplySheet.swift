import AppKit
import SwiftUI

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

            if !model.attachments.isEmpty { attachments }

            HStack {
                Button(action: addImage) {
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

            HStack {
                if justSent {
                    Label("Reply sent", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel", action: onClose).disabled(justSent || model.isSending)
                Button(model.isSending ? "Sending…" : "Reply") {
                    Task {
                        guard await model.send() else { return }
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

    private var attachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.attachments) { attachment in
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            if let img = NSImage(data: attachment.imageData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            Button(role: .destructive) {
                                removeAttachment(id: attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .help("Remove image")
                        }
                        TextField("Alt text", text: bindingForAltText(id: attachment.id))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func bindingForAltText(id: UUID) -> Binding<String> {
        Binding {
            model.attachments.first { $0.id == id }?.altText ?? ""
        } set: { newValue in
            guard let index = model.attachments.firstIndex(where: { $0.id == id }) else { return }
            model.attachments[index].altText = newValue
        }
    }

    private func addImage() {
        guard model.attachments.count < TargetLimits.imageMax else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let remaining = TargetLimits.imageMax - model.attachments.count
        var failed: [String] = []
        for url in panel.urls.prefix(remaining) {
            if let data = try? Data(contentsOf: url) {
                model.attachments.append(Attachment(imageData: data))
            } else {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty { model.errorMessage = "Couldn't read \(failed.joined(separator: ", "))." }
    }

    private func removeAttachment(id: UUID) {
        model.attachments.removeAll { $0.id == id }
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
