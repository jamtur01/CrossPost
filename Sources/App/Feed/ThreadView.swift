import SwiftUI

/// An in-place thread: the focused post (expanded) with its ancestors above and
/// replies below. Tapping a surrounding post navigates deeper.
struct ThreadView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let focusedPost: FeedPost
    let push: (FeedRoute) -> Void

    @State private var list: PostList
    @State private var replyTarget: FeedPost?
    @State private var loading = true

    private var accent: Color { panel.target.accent }

    init(panel: FeedPanelModel, store: AccountStore, post: FeedPost,
         push: @escaping (FeedRoute) -> Void) {
        self.panel = panel
        self.store = store
        self.focusedPost = post
        self.push = push
        _list = State(initialValue: PostList(panel: panel))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list.posts) { row in
                    let isFocused = row.id == focusedPost.id
                    FeedPostView(
                        post: row,
                        accent: accent,
                        onReply: { replyTarget = row },
                        onLike: { list.toggleLike(row) },
                        onRepost: { list.toggleRepost(row) },
                        onOpen: { panel.openInBrowser(row) },
                        onOpenProfile: { push(.profile(row.profileRef())) },
                        onOpenURL: { panel.openLink($0, push: push) },
                        isMine: panel.isMine(row),
                        onBookmark: { list.setBookmarked(!row.isBookmarked, row) },
                        onDelete: { list.delete(row) },
                        onPin: { list.setPinned(!row.isPinned, row) },
                        onLikedBy: { push(.profileList(ProfileListRef(kind: .likedBy, post: row))) },
                        onRepostedBy: { push(.profileList(ProfileListRef(kind: .repostedBy, post: row))) },
                        onOpenDetail: isFocused ? nil : { push(.thread(row)) },
                        onReport: panel.isMine(row) ? nil : { reason, comment in
                            try await panel.report(post: row, reason: reason, comment: comment)
                        },
                        onQuote: { text, visibility in
                            try await panel.quote(post: row, text: text, visibility: visibility)
                        },
                        inTimeline: !isFocused,
                        expanded: isFocused)
                        .padding(isFocused ? 16 : 0)
                        .background(isFocused ? accent.opacity(0.06) : .clear)
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            let thread = await panel.thread(of: focusedPost)
            // Read the focused post after the fetch so a poll during loading can't
            // leave it showing stale counts.
            let live = panel.posts.first { $0.id == focusedPost.id } ?? focusedPost
            // Guard against a service returning the focused post inside its own
            // context, which would duplicate its id in the ForEach.
            let ancestors = thread.ancestors.filter { $0.id != focusedPost.id }
            let descendants = thread.descendants.filter { $0.id != focusedPost.id }
            list.posts = ancestors + [live] + descendants
            loading = false
        }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }
}
