import SwiftUI

/// The one wiring of a `FeedPost` into `FeedPostView`, shared by every surface that
/// lists posts — the timeline and the thread/profile/saved/search routes. Mutations
/// go through the row's `OptimisticPostHost` (the panel timeline or a route's
/// `PostList`); panel-level actions (open, report, quote, edit, profile checks) go
/// through `panel`; navigation goes through `push`.
struct FeedRow: View {
    let post: FeedPost
    /// The collection that owns this row's optimistic like/repost/bookmark/pin/delete.
    let host: any OptimisticPostHost
    let panel: FeedPanelModel
    let accent: Color
    let push: (FeedRoute) -> Void
    let onReply: (FeedPost) -> Void
    /// True for the expanded, focused post in a thread: bigger avatar, full-width
    /// media, no open-detail tap, and route-level padding/highlight.
    var focused = false
    /// Threads already show ancestors inline, so they suppress the "in reply to" link.
    var showsParentLink = true

    var body: some View {
        FeedPostView(
            post: post,
            accent: accent,
            onReply: { onReply(post) },
            onLike: { host.toggleLike(post) },
            onRepost: { host.toggleRepost(post) },
            onOpen: { panel.openInBrowser(post) },
            onOpenProfile: { push(.profile(post.profileRef())) },
            onOpenURL: { panel.openLink($0, push: push) },
            isMine: panel.isMine(post),
            onBookmark: { host.setBookmarked(!post.isBookmarked, on: post) },
            onDelete: { host.delete(post) },
            onPin: { host.setPinned(!post.isPinned, on: post) },
            onLikedBy: { push(.profileList(ProfileListRef(kind: .likedBy, post: post))) },
            onRepostedBy: { push(.profileList(ProfileListRef(kind: .repostedBy, post: post))) },
            onShowParent: (showsParentLink && post.isReply) ? { push(.thread(post)) } : nil,
            onOpenDetail: focused ? nil : { push(.thread(post)) },
            onReport: panel.isMine(post) ? nil : { reason, comment in
                try await panel.report(post: post, reason: reason, comment: comment)
            },
            onQuote: { text, visibility in
                _ = try await panel.quote(post: post, text: text, visibility: visibility)
            },
            onEdit: postEditActions(for: post, panel, onUpdated: { host.replace($0) }),
            onCopyLink: { panel.copyLink(post) },
            inTimeline: !focused,
            expanded: focused)
        .padding(focused ? 16 : 0)
        .background(focused ? accent.opacity(0.06) : .clear)
    }
}
