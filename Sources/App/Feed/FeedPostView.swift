import SwiftUI

struct FeedPostView: View {
    let post: FeedPost
    var accent: Color = .accentColor
    var onReply: () -> Void = {}
    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}
    var onOpen: () -> Void = {}
    var onShowParent: (() -> Void)?
    var showActions: Bool = true
    /// Timeline rows get hover highlight + a separator; sheet previews don't.
    var inTimeline: Bool = true

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            contextLine
            header
            Text(post.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            images
            if showActions { actionBar }
        }
        .padding(.horizontal, inTimeline ? 16 : 0)
        .padding(.vertical, inTimeline ? 12 : 0)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if inTimeline { Divider().opacity(0.6) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var contextLine: some View {
        if post.isReply, let onShowParent {
            Button(action: onShowParent) {
                Label("In reply to a post", systemImage: "arrowshape.turn.up.left.fill")
                    .font(.caption)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        if let boostedBy = post.boostedBy {
            Label("\(boostedBy) boosted", systemImage: "arrow.2.squarepath")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: post.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.06)))

            VStack(alignment: .leading, spacing: 1) {
                Text(post.authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(post.authorHandle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(post.date, format: .relative(presentation: .numeric))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var images: some View {
        if !post.images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(post.images) { image in
                        AsyncImage(url: image.url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: 140, height: 105)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(image.altText)
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionButton("arrowshape.turn.up.left", active: false, tint: accent,
                         help: "Reply", action: onReply)
            actionButton(post.isReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
                         active: post.isReposted, tint: .green,
                         help: "Repost", action: onRepost)
            actionButton(post.isLiked ? "heart.fill" : "heart",
                         active: post.isLiked, tint: .pink,
                         help: "Like", action: onLike)
            Spacer()
            actionButton("safari", active: false, tint: accent,
                         help: "Open in browser", action: onOpen)
        }
        .padding(.top, 2)
    }

    private func actionButton(_ symbol: String, active: Bool, tint: Color,
                              help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(active ? tint : Color.secondary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: some View {
        Rectangle().fill(hovering && inTimeline ? Color.primary.opacity(0.04) : .clear)
    }
}
