import SwiftUI

struct PostCardView: View {
    @Binding var post: DraftPost
    let index: Int
    let limit: Int
    var showLabel: Bool = true   // "Post N" + remove (thread mode)
    var fills: Bool = false      // editor expands to fill available height
    let canRemove: Bool
    let onRemove: () -> Void
    var onError: (String) -> Void = { _ in }

    /// Warn (orange) once within this many graphemes of the limit.
    private static let warnWithin = 20

    private var count: Int { PostValidator.graphemeCount(post.text) }
    private var canAddImages: Bool { post.attachments.count < TargetLimits.imageMax }

    private var counterColor: Color {
        if count > limit { return .red }
        if count >= limit - Self.warnWithin { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showLabel {
                HStack {
                    Text("Post \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if canRemove {
                        Button(role: .destructive, action: onRemove) {
                            Image(systemName: "trash").font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this post")
                    }
                }
            }

            editor

            if !post.attachments.isEmpty { attachments }

            HStack(spacing: 12) {
                Button(action: addImage) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(!canAddImages)
                .help(canAddImages ? "Add image" : "Maximum \(TargetLimits.imageMax) images")

                Spacer()

                Text("\(count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(counterColor)
            }
        }
        .padding(14)
        .frame(maxHeight: fills ? .infinity : nil)
        .cardSurface()
    }

    private var editor: some View {
        PlainTextEditor(text: $post.text)
            .frame(minHeight: fills ? 160 : 90, maxHeight: fills ? .infinity : 200)
            .overlay(alignment: .topLeading) {
                if post.text.isEmpty {
                    Text("What's on your mind?")
                        .font(Theme.content).foregroundStyle(.tertiary)
                        .padding(.leading, 5).padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    private var attachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach($post.attachments) { $attachment in
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            if let img = NSImage(data: attachment.imageData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
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
                        TextField("Alt text", text: $attachment.altText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func addImage() {
        guard canAddImages else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let remaining = TargetLimits.imageMax - post.attachments.count
        var failed: [String] = []
        for url in panel.urls.prefix(remaining) {
            if let data = try? Data(contentsOf: url) {
                post.attachments.append(Attachment(imageData: data))
            } else {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty { onError("Couldn't read \(failed.joined(separator: ", ")).") }
    }

    private func removeAttachment(id: UUID) {
        post.attachments.removeAll { $0.id == id }
    }
}
