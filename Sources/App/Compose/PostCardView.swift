import SwiftUI

struct PostCardView: View {
    @Binding var post: DraftPost
    let index: Int
    let canRemove: Bool
    let onRemove: () -> Void

    /// Warn (orange) once within this many graphemes of the Bluesky limit.
    private static let warnWithin = 20

    private var count: Int { PostValidator.graphemeCount(post.text) }

    private var counterColor: Color {
        if count > TargetLimits.blueskyMax { return .red }
        if count >= TargetLimits.blueskyMax - Self.warnWithin { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Post \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)/\(TargetLimits.blueskyMax)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(counterColor)
                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this post")
                }
            }
            PlainTextEditor(text: $post.text)
                .frame(minHeight: 100, maxHeight: 220)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(alignment: .topLeading) {
                    if post.text.isEmpty {
                        Text("What's on your mind?")
                            .font(Theme.content).foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))

            if !post.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach($post.attachments) { $attachment in
                            VStack(spacing: 6) {
                                if let img = NSImage(data: attachment.imageData) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(6)
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

            Button(action: addImage) {
                Label("Add Image…", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .cardSurface()
    }

    private func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            post.attachments.append(Attachment(imageData: data))
        }
    }
}
