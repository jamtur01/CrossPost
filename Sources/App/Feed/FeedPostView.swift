import SwiftUI

struct FeedPostView: View {
    let post: FeedPost
    /// Session reveal state for content warnings and sensitive media.
    let reveals: PostReveals
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
    /// Posts a quote of this post; when nil, the Quote menu item is hidden.
    var onQuote: ((String, PostVisibility) async throws -> Void)?
    /// Edits this post; when nil, the Edit menu item is hidden (Mastodon only).
    var onEdit: PostEditActions?
    var onCopyLink: () -> Void = {}
    var showActions: Bool = true
    /// The focused post in a thread: larger type and avatar, full-width media, and no
    /// row padding, hover highlight, or separator. Otherwise it is a timeline row.
    var expanded: Bool = false

    @State private var hovering = false
    @State private var hoveringParentLink = false
    @State private var reporting = false
    @State private var quoting = false
    @State private var editing = false
    @State private var confirmingDelete = false
    @State var imageRetryIDs: [URL: UUID] = [:]
    /// Contexts without a lightbox open the image through their URL action.
    @Environment(ImageLightbox.self) var lightbox: ImageLightbox?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var bodyFontSize: CGFloat {
        expanded ? Theme.expandedContentSize : Theme.timelineContentSize
    }

    private var authorNameFont: Font {
        expanded ? Theme.nameLarge : Theme.timelineName
    }

    /// Point size of `authorNameFont`, for sizing custom emoji in the name.
    private var authorNamePointSize: CGFloat {
        expanded ? 16 : 14
    }

    private var authorHandleFont: Font {
        expanded ? Theme.handle : Theme.timelineHandle
    }

    private var avatarSize: CGFloat {
        expanded ? Theme.avatarLarge : Theme.timelineAvatar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.componentSpacing) {
            contextLine
            header
            if let warning = post.contentWarning {
                contentWarningRow(warning)
            }
            if reveals.showsContent(of: post) {
                bodyText
                images
                if let card = post.card {
                    LinkCardView(card: card, accent: accent, sensitive: cardSensitiveMedia, onOpen: onOpenURL)
                }
                if let quoted = post.quoted {
                    QuoteCardView(quote: quoted, accent: accent, reveals: reveals, onOpen: onOpenURL)
                }
            }
            if showActions {
                actionBar
            }
        }
        .padding(.horizontal, expanded ? 0 : Theme.timelineRowPaddingH)
        .padding(.vertical, expanded ? 0 : Theme.timelineRowPaddingV)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if !expanded {
                Divider().opacity(0.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpenDetail?() }
        .accessibilityAction(named: "Open thread") { onOpenDetail?() }
        .sheet(isPresented: $reporting) {
            if let onReport {
                ReportSheet(subjectLabel: "this post", accent: accent,
                            submit: onReport) { reporting = false }
            }
        }
        .sheet(isPresented: $quoting) {
            if let onQuote {
                QuoteSheet(post: post, accent: accent, submit: onQuote) { quoting = false }
            }
        }
        .sheet(isPresented: $editing) {
            if let onEdit {
                EditSheet(post: post, accent: accent, actions: onEdit) { editing = false }
            }
        }
        .confirmationDialog(
            "Delete this post from \(post.target.displayName)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }

    /// Body text. Selectable everywhere so the body can be copied; in timeline rows
    /// a drag selects text while a plain click opens the thread.
    private var bodyText: some View {
        PostBody(text: post.text, accent: accent, cacheKey: post.id, emojis: post.emojis,
                 fontSize: bodyFontSize, onTap: onOpenDetail, onOpenURL: onOpenURL)
    }

    @ViewBuilder
    private var contextLine: some View {
        // The boost comes first: it explains why the post is in this timeline,
        // while the reply line describes the post itself.
        if let boostedBy = post.boostedBy {
            let verb = switch post.target {
            case .mastodon: "boosted"
            case .bluesky: "reposted"
            }
            Label {
                EmojiText("\(boostedBy) \(verb)", emojis: post.emojis, pointSize: 12)
            } icon: {
                Image(systemName: "arrow.2.squarepath")
            }
            .font(Theme.timelineContext)
            .foregroundStyle(.secondary)
        }
        // Both context lines are quiet secondary chrome; the reply link shows the
        // network accent only on hover, so it reads as tappable without outranking
        // the author name.
        if post.isReply, let onShowParent {
            Button(action: onShowParent) {
                Label("In reply to \(post.replyToHandle ?? "a post")",
                      systemImage: "arrowshape.turn.up.left")
                    .font(Theme.timelineContext)
                    .foregroundStyle(hoveringParentLink ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringParentLink)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hoveringParentLink = $0 }
            .help("Show thread")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpenProfile) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(url: post.avatarURL, size: avatarSize)

                    VStack(alignment: .leading, spacing: 2) {
                        EmojiText(post.authorName, emojis: post.emojis, pointSize: authorNamePointSize)
                            .font(authorNameFont)
                            .lineLimit(1)
                        Text(post.authorHandle)
                            .font(authorHandleFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Open profile")

            Spacer(minLength: 6)
            if let visibility = visibilityBadge {
                Image(systemName: visibility.symbol)
                    .font(Theme.timelineMeta)
                    .foregroundStyle(.secondary)
                    .help(visibility.label)
                    .accessibilityLabel(visibility.label)
            }
            relativeTimestamp(post.date, font: Theme.timelineMeta)
        }
    }

    /// Narrow columns with four-character counts ("1.2K") don't fit the standard
    /// gap, so the bar tightens its spacing rather than wrapping or shrinking type.
    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            actionRow(spacing: Theme.actionGap)
            actionRow(spacing: Theme.actionGapNarrow)
        }
        .padding(.top, 4)
    }

    private func actionRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            postActionButton("bubble", count: post.replyCount, active: false,
                             tint: accent, help: "Reply", action: onReply)
            postActionButton("arrow.2.squarepath", count: post.repostCount, active: post.isReposted,
                             tint: Theme.repostTint, help: "Repost", action: onRepost)
            postActionButton(post.isLiked ? "heart.fill" : "heart", count: post.likeCount,
                             active: post.isLiked, tint: Theme.likeTint, help: "Like", action: onLike)
            Spacer(minLength: 0)
            postActionButton(post.isBookmarked ? "bookmark.fill" : "bookmark", active: post.isBookmarked,
                             tint: .primary, help: post.isBookmarked ? "Remove Bookmark" : "Bookmark",
                             action: onBookmark)
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            if onQuote != nil {
                Button { quoting = true } label: {
                    Label("Quote", systemImage: "quote.bubble")
                }
            }
            if post.likeCount > 0 {
                Button(action: onLikedBy) { Label("Liked by…", systemImage: "heart") }
            }
            if post.repostCount > 0 {
                Button(action: onRepostedBy) { Label("Reposted by…", systemImage: "arrow.2.squarepath") }
            }
            Divider()
            if post.webURL != nil {
                Button(action: onCopyLink) { Label("Copy Link", systemImage: "link") }
            }
            Button(action: onOpen) { Label("Open in Browser", systemImage: "safari") }
            if isMine {
                if post.target == .mastodon {
                    if onEdit != nil {
                        Button { editing = true } label: { Label("Edit…", systemImage: "pencil") }
                    }
                    Button(action: onPin) {
                        Label(post.isPinned ? "Unpin" : "Pin to Profile", systemImage: "pin")
                    }
                }
                Divider()
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete…", systemImage: "trash")
                }
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

    private var rowBackground: some View {
        Rectangle()
            .fill(hovering && !expanded ? Theme.hoverFill : .clear)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
