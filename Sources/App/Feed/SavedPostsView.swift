import SwiftUI

/// Pages through the signed-in user's bookmarks or likes as the reader scrolls:
/// each `loadMore()` appends the next page, skipping posts already shown, until the
/// network has no more. A failed page keeps what's loaded and waits for `retry()`.
@MainActor
@Observable
final class SavedPostsModel {
    let list: PostList
    private(set) var cursor: String?
    private(set) var reachedEnd = false
    private(set) var loadError: String?
    @ObservationIgnored private let panel: FeedPanelModel
    @ObservationIgnored private let kind: SavedKind

    /// Whether another page should load once the end of the list is in view.
    var wantsMore: Bool {
        !reachedEnd && loadError == nil
    }

    init(panel: FeedPanelModel, kind: SavedKind) {
        self.panel = panel
        self.kind = kind
        list = PostList(panel: panel)
    }

    func loadMore() async {
        guard wantsMore else { return }
        let requested = cursor
        do {
            let page = kind == .bookmarks
                ? try await panel.bookmarkedPosts(cursor: requested)
                : try await panel.likedPosts(cursor: requested)
            guard !Task.isCancelled else { return }
            var seen = Set(list.posts.map(\.id))
            list.posts += page.posts.filter { seen.insert($0.id).inserted }
            cursor = page.cursor
            // A cursor that doesn't advance would request the same page forever.
            reachedEnd = page.cursor == nil || page.cursor == requested
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.userMessage
        }
    }

    func retry() {
        loadError = nil
    }
}

/// The signed-in user's bookmarked or liked posts, shown as a pushed route.
struct SavedPostsView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let kind: SavedKind
    let push: (FeedRoute) -> Void

    @State private var model: SavedPostsModel
    @State private var replyTarget: FeedPost?

    private var accent: Color {
        panel.target.accent
    }

    init(
        panel: FeedPanelModel, store: AccountStore, kind: SavedKind,
        push: @escaping (FeedRoute) -> Void
    ) {
        self.panel = panel
        self.store = store
        self.kind = kind
        self.push = push
        _model = State(initialValue: SavedPostsModel(panel: panel, kind: kind))
    }

    var body: some View {
        let list = model.list
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list.posts) { row in
                    FeedRow(post: row, host: list, panel: panel, accent: accent,
                            push: push, onReply: { replyTarget = $0 })
                }
                if model.wantsMore {
                    // Loads the next page when the end of the list scrolls into view, and
                    // again after each page while it stays in view. SwiftUI cancels the
                    // load when it scrolls away or the view goes.
                    Color.clear.frame(height: 1)
                        .task(id: model.cursor) { await model.loadMore() }
                }
            }
            .scrollTargetLayout()
            listLoadFooter(loading: model.wantsMore, loadError: model.loadError, isEmpty: list.posts.isEmpty,
                           emptyState: ("No \(kind.title.lowercased()) yet", kind.icon)) {
                model.retry()
            }
        }
        .scrollContentBackground(.hidden)
        .feedKeyboardNavigation(posts: list.posts, hosts: [list], reply: { replyTarget = $0 },
                                open: { push(.thread($0)) })
        .background(Color(nsColor: .textBackgroundColor))
        .onDisappear { list.invalidateOptimisticMutations() }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }
}
