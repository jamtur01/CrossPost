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
    @State private var loadError: String?

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
                    FeedRow(post: row, host: list, panel: panel, accent: accent,
                            push: push, onReply: { replyTarget = $0 },
                            focused: row.id == focusedPost.id, showsParentLink: false)
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else if let loadError {
                    // The focused post still shows; the thread context failed to load.
                    ErrorStateView(message: loadError, fills: false) { Task { await load() } }
                }
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
            let thread = try await panel.thread(of: focusedPost)
            // Read the focused post after the fetch so a poll/like during loading is
            // reflected (freshest counts and like/repost state win).
            let live = panel.posts.first { $0.id == focusedPost.id } ?? focusedPost
            // Guard against a service returning the focused post inside its own
            // context, which would duplicate its id in the ForEach.
            let ancestors = thread.ancestors.filter { $0.id != focusedPost.id }
            let descendants = thread.descendants.filter { $0.id != focusedPost.id }
            list.posts = ancestors + [live] + descendants
        } catch {
            let live = panel.posts.first { $0.id == focusedPost.id } ?? focusedPost
            list.posts = [live]   // keep the focused post; surface the context failure
            loadError = error.userMessage
        }
        loading = false
    }
}
