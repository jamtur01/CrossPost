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
    @State private var loadToken = 0

    @State private var replyDisclosure = ThreadReplyDisclosure()
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
                if !loading, loadError == nil, replyDisclosure.remainingCount > 0 {
                    Button(disclosureButtonTitle) {
                        list.posts.append(contentsOf: replyDisclosure.revealNext())
                    }
                    .padding(.vertical, 12)
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else if let loadError {
                    // The focused post still shows; the thread context failed to load.
                    ErrorStateView(message: loadError, fills: false) { loadToken += 1 }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: loadToken) { await load() }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }

    private var disclosureButtonTitle: String {
        let nextCount = min(ThreadReplyDisclosure.chunkSize, replyDisclosure.remainingCount)
        let unit = nextCount == 1 ? "reply" : "replies"
        return "Show \(nextCount) more \(unit) (\(replyDisclosure.remainingCount) remaining)"
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let thread = try await panel.thread(of: focusedPost)
            guard !Task.isCancelled else { return }
            // Read the focused post after the fetch so a poll/like during loading is
            // reflected (freshest counts and like/repost state win).
            let live = panel.posts.first { $0.id == focusedPost.id } ?? focusedPost
            // Guard against a service returning the focused post inside its own
            // context, which would duplicate its id in the ForEach.
            list.posts = replyDisclosure.replace(
                ancestors: thread.ancestors,
                focused: live,
                descendants: thread.descendants
            )
        } catch {
            guard !Task.isCancelled else { return }
            let live = panel.posts.first { $0.id == focusedPost.id } ?? focusedPost
            replyDisclosure.reset()
            list.posts = [live]   // keep the focused post; surface the context failure
            loadError = error.userMessage
        }
        loading = false
    }
}

struct ThreadReplyDisclosure {
    static let chunkSize = 25

    private var remaining: ArraySlice<FeedPost> = []

    var remainingCount: Int {
        remaining.count
    }

    mutating func replace(
        ancestors: [FeedPost],
        focused: FeedPost,
        descendants: [FeedPost]
    ) -> [FeedPost] {
        let ancestors = ancestors.filter { $0.id != focused.id }
        let descendants = descendants.filter { $0.id != focused.id }
        let initiallyVisible = descendants.prefix(Self.chunkSize)
        remaining = descendants.dropFirst(initiallyVisible.count)
        return ancestors + [focused] + Array(initiallyVisible)
    }

    mutating func revealNext() -> [FeedPost] {
        let next = remaining.prefix(Self.chunkSize)
        remaining = remaining.dropFirst(next.count)
        return Array(next)
    }

    mutating func reset() {
        remaining = []
    }
}
