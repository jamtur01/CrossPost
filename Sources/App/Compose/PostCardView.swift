import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PostCardView: View {
    @Binding var post: DraftPost
    let index: Int
    let limit: Int
    var showLabel: Bool = true   // "Post N" + remove (thread mode)
    var fills: Bool = false      // editor expands to fill available height
    let canRemove: Bool
    let onRemove: () -> Void
    var onError: (String) -> Void = { _ in }

    @State private var isDropTarget = false

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

            if !post.attachments.isEmpty { AttachmentBar(attachments: $post.attachments) }

            HStack(spacing: 12) {
                Button { ImageAttaching.pick(into: $post.attachments, onError: onError) } label: {
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
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .fill(Color.accentColor.opacity(0.06)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTarget) { providers in
            ImageAttaching.load(providers, into: $post.attachments, onError: onError)
            return true
        }
        .onPasteCommand(of: [.image, .fileURL]) {
            ImageAttaching.load($0, into: $post.attachments, onError: onError)
        }
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
}
