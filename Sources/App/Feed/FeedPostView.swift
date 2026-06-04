import SwiftUI

struct FeedPostView: View {
    let post: FeedPost
    var accent: Color = .accentColor
    var onReply: () -> Void = {}
    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}
    var onOpen: () -> Void = {}
    var onShowParent: (() -> Void)?
    var onOpenDetail: (() -> Void)?
    var showActions: Bool = true
    /// Timeline rows get hover highlight + a separator; sheet/detail views don't.
    var inTimeline: Bool = true
    /// Detail (pop-out) view shows a bigger avatar and full-width media.
    var expanded: Bool = false

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            contextLine
            header
            Text(styledText)
                .font(expanded ? .title3 : .body)
                .tint(accent)
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
        .onTapGesture { onOpenDetail?() }
    }

    private var styledText: AttributedString {
        RichText.styled(String(post.text.characters), accent: accent)
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
            .frame(width: expanded ? 52 : 42, height: expanded ? 52 : 42)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.06)))

            VStack(alignment: .leading, spacing: 1) {
                Text(post.authorName)
                    .font(.system(size: expanded ? 16 : 14, weight: .semibold))
                    .lineLimit(1)
                Text(post.authorHandle)
                    .font(.system(size: expanded ? 13 : 12))
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
            if expanded {
                VStack(spacing: 8) {
                    ForEach(post.images) { image in
                        AsyncImage(url: image.url) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(height: 200)
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(image.altText)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.images) { image in
                            AsyncImage(url: image.url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 150, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(image.altText)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            countAction("bubble.left", count: post.replyCount, active: false,
                        tint: accent, help: "Reply", action: onReply)
            countAction("arrow.2.squarepath", count: post.repostCount, active: post.isReposted,
                        tint: .green, help: "Repost", action: onRepost)
            countAction(post.isLiked ? "heart.fill" : "heart", count: post.likeCount,
                        active: post.isLiked, tint: .pink, help: "Like", action: onLike)
            Spacer()
            Button(action: onOpen) {
                Image(systemName: "safari")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in browser")
        }
        .padding(.top, 2)
    }

    private func countAction(_ symbol: String, count: Int, active: Bool, tint: Color,
                             help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13))
                if count > 0 {
                    Text(count.formatted(.number.notation(.compactName)))
                        .font(.system(size: 12).monospacedDigit())
                }
            }
            .foregroundStyle(active ? tint : Color.secondary)
            .padding(.vertical, 4)
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: some View {
        Rectangle().fill(hovering && inTimeline ? Color.primary.opacity(0.04) : .clear)
    }
}
