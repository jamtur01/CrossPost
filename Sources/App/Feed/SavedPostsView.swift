import SwiftUI

/// The signed-in user's bookmarked or liked posts, shown as a pushed route.
struct SavedPostsView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let kind: SavedKind
    let push: (FeedRoute) -> Void

    @State private var list: PostList
    @State private var replyTarget: FeedPost?
    @State private var loading = true

    private var accent: Color { panel.target.accent }

    init(panel: FeedPanelModel, store: AccountStore, kind: SavedKind,
         push: @escaping (FeedRoute) -> Void) {
        self.panel = panel
        self.store = store
        self.kind = kind
        self.push = push
        _list = State(initialValue: PostList(panel: panel))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list.posts) { row in
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
                        onShowParent: row.isReply ? { push(.thread(row)) } : nil,
                        onOpenDetail: { push(.thread(row)) },
                        onReport: panel.isMine(row) ? nil : { reason, comment in
                            try await panel.report(post: row, reason: reason, comment: comment)
                        },
                        onQuote: { text, visibility in
                            _ = try await panel.quote(post: row, text: text, visibility: visibility)
                        },
                        onEdit: postEditActions(for: row, panel),
                        onCopyLink: { panel.copyLink(row) })
                }
            }
            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if list.posts.isEmpty {
                emptyState
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            list.posts = kind == .bookmarks
                ? await panel.bookmarkedPosts()
                : await panel.likedPosts()
            loading = false
        }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: kind.icon).font(.largeTitle).foregroundStyle(.secondary)
            Text("No \(kind.title.lowercased()) yet")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}
