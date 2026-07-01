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
    @State private var loadError: String?

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
                    FeedRow(post: row, host: list, panel: panel, accent: accent,
                            push: push, onReply: { replyTarget = $0 })
                }
            }
            listLoadFooter(loading: loading, loadError: loadError, isEmpty: list.posts.isEmpty,
                           emptyText: "No \(kind.title.lowercased()) yet", emptyImage: kind.icon) {
                Task { await load() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task { await load() }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            list.posts = kind == .bookmarks
                ? try await panel.bookmarkedPosts()
                : try await panel.likedPosts()
        } catch {
            loadError = error.userMessage
        }
        loading = false
    }
}
