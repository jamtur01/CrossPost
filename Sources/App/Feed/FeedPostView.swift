import SwiftUI
import AppKit

struct FeedPostView: View {
    let post: FeedPost
    var accent: Color = .accentColor
    var onReply: () -> Void = {}
    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}
    var onOpen: () -> Void = {}
    var onOpenProfile: () -> Void = {}
    var onOpenURL: (URL) -> Void = { _ in }
    var isMine: Bool = false
    var onBookmark: () -> Void = {}
    var onDelete: () -> Void = {}
    var onPin: () -> Void = {}
    var onLikedBy: () -> Void = {}
    var onRepostedBy: () -> Void = {}
    var onShowParent: (() -> Void)?
    var onOpenDetail: (() -> Void)?
    /// Files a moderation report; when nil, the Report menu item is hidden.
    var onReport: ((ReportReason, String) async throws -> Void)?
    var showActions: Bool = true
    /// Timeline rows get hover highlight + a separator; sheet/detail views don't.
    var inTimeline: Bool = true
    /// Detail (pop-out) view shows a bigger avatar and full-width media.
    var expanded: Bool = false

    @State private var hovering = false
    @State private var reporting = false
    // Optional: present where no lightbox is installed (e.g. preview/sheet contexts)
    // simply leaves images non-poppable rather than crashing.
    @Environment(ImageLightbox.self) private var lightbox: ImageLightbox?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.componentSpacing) {
            contextLine
            header
            bodyText
            images
            if let card = post.card {
                LinkCardView(card: card, accent: accent, onOpen: onOpenURL)
            }
            if let quoted = post.quoted {
                QuoteCardView(quote: quoted, accent: accent, onOpen: onOpenURL)
            }
            if showActions { actionBar }
        }
        .padding(.horizontal, inTimeline ? Theme.rowPaddingH : 0)
        .padding(.vertical, inTimeline ? Theme.rowPaddingV : 0)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if inTimeline { Divider().opacity(0.5) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpenDetail?() }
        .sheet(isPresented: $reporting) {
            if let onReport {
                ReportSheet(subjectLabel: "this post", accent: accent,
                            submit: onReport) { reporting = false }
            }
        }
    }

    private var styledText: AttributedString {
        RichText.styled(post.text, accent: accent, cacheKey: post.id)
    }

    /// Body text. Selectable everywhere so the body can be copied; in timeline rows
    /// a drag selects text while a plain click still falls through to open the thread.
    private var bodyText: some View {
        Text(styledText)
            .font(expanded ? Theme.contentLarge : Theme.content)
            .tint(accent)
            .lineSpacing(Theme.bodyLineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            // Route link taps (mentions, URLs) through the app so profile links can
            // open in-app instead of always deferring to the system browser.
            .environment(\.openURL, OpenURLAction { url in onOpenURL(url); return .handled })
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var contextLine: some View {
        if post.isReply, let onShowParent {
            Button(action: onShowParent) {
                Label("In reply to a post", systemImage: "arrowshape.turn.up.left.fill")
                    .font(Theme.context)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        if let boostedBy = post.boostedBy {
            Label("\(boostedBy) boosted", systemImage: "arrow.2.squarepath")
                .font(Theme.context)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpenProfile) {
                HStack(alignment: .top, spacing: 10) {
                    AsyncImage(url: post.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.quaternary)
                    }
                    .frame(width: expanded ? Theme.avatarLarge : Theme.avatar,
                           height: expanded ? Theme.avatarLarge : Theme.avatar)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(expanded ? Theme.nameLarge : Theme.name)
                            .lineLimit(1)
                        Text(post.authorHandle)
                            .font(Theme.handle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("Open profile")

            Spacer(minLength: 6)
            if let visibility = visibilityBadge {
                Image(systemName: visibility.symbol)
                    .font(Theme.meta)
                    .foregroundStyle(.tertiary)
                    .help(visibility.label)
                    .accessibilityLabel(visibility.label)
            }
            Text(post.date, format: .relative(presentation: .numeric))
                .font(Theme.meta)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }

    /// Indicator for a non-public post (Mastodon visibility). Public posts and
    /// Bluesky posts (which have no per-post visibility) show nothing.
    private var visibilityBadge: (symbol: String, label: String)? {
        switch post.visibility {
        case "unlisted": return ("moon", "Unlisted")
        case "private": return ("lock.fill", "Followers only")
        case "direct": return ("envelope.fill", "Direct message")
        default: return nil
        }
    }

    @ViewBuilder
    private var images: some View {
        if !post.images.isEmpty {
            if expanded {
                VStack(spacing: 8) {
                    ForEach(post.images) { media in
                        mediaView(media, fit: true)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.images) { media in
                            mediaView(media, fit: false)
                                .frame(width: 156, height: 116)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaView(_ media: FeedImage, fit: Bool) -> some View {
        switch media.kind {
        case .image:
            staticImage(media.url, fit: fit)
                .accessibilityLabel(media.altText.isEmpty ? "Image" : media.altText)
        case .gif:
            MotionMedia(media: media, fit: fit, badge: "GIF") { active in
                AnimatedGIFView(url: media.url, isActive: active)
            }
        case .video:
            MotionMedia(media: media, fit: fit, badge: nil) { active in
                LoopingVideoView(url: media.url,
                                 gravity: fit ? .resizeAspect : .resizeAspectFill, isActive: active)
            }
        }
    }

    private func staticImage(_ url: URL, fit: Bool) -> some View {
        AsyncImage(url: url) { img in
            img.resizable().aspectRatio(contentMode: fit ? .fit : .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: Theme.mediaCorner).fill(.quaternary).frame(height: 120)
        }
        // Tap pops the image out; takes precedence over the row's open-thread tap.
        .onTapGesture { lightbox?.present(url) }
        .onHover { hovering in
            guard lightbox != nil else { return }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var actionBar: some View {
        HStack(spacing: Theme.actionGap) {
            countAction("bubble", count: post.replyCount, active: false,
                        tint: accent, help: "Reply", action: onReply)
            countAction("arrow.2.squarepath", count: post.repostCount, active: post.isReposted,
                        tint: .green, help: "Repost", action: onRepost)
            countAction(post.isLiked ? "heart.fill" : "heart", count: post.likeCount,
                        active: post.isLiked, tint: .pink, help: "Like", action: onLike)
            Spacer(minLength: 0)
            iconAction("square.and.arrow.up", help: "Open in browser", action: onOpen)
            moreMenu
        }
        .padding(.top, 4)
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onBookmark) {
                Label(post.isBookmarked ? "Remove Bookmark" : "Bookmark",
                      systemImage: post.isBookmarked ? "bookmark.fill" : "bookmark")
            }
            if post.likeCount > 0 {
                Button(action: onLikedBy) { Label("Liked by…", systemImage: "heart") }
            }
            if post.repostCount > 0 {
                Button(action: onRepostedBy) { Label("Reposted by…", systemImage: "arrow.2.squarepath") }
            }
            Divider()
            Button(action: onOpen) { Label("Open in Browser", systemImage: "safari") }
            if isMine {
                if post.target == .mastodon {
                    Button(action: onPin) {
                        Label(post.isPinned ? "Unpin" : "Pin to Profile", systemImage: "pin")
                    }
                }
                Divider()
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            } else if onReport != nil {
                Divider()
                Button(role: .destructive) { reporting = true } label: {
                    Label("Report…", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.action)
                .foregroundStyle(.secondary)
                .padding(.vertical, 5).padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private func countAction(_ symbol: String, count: Int, active: Bool, tint: Color,
                             help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(Theme.action)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(active ? tint : Color.secondary)
                if count > 0 {
                    Text(count.formatted(.number.notation(.compactName)))
                        .font(Theme.count)
                        .foregroundStyle(active ? tint : Color.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .animation(.snappy, value: active)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconAction(_ symbol: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.action)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4).padding(.horizontal, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(hovering && inTimeline ? Theme.hoverFill : .clear)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
