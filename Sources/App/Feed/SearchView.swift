import SwiftUI

/// Search this network for accounts and posts. Debounced; results are grouped
/// into People and Posts, each row navigating into the app.
struct SearchView: View {
    let panel: FeedPanelModel
    let store: AccountStore
    let push: (FeedRoute) -> Void

    @State private var query = ""
    @State private var results = SearchResults()
    @State private var postList: PostList
    @State private var replyTarget: FeedPost?
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    private var accent: Color { panel.target.accent }

    init(panel: FeedPanelModel, store: AccountStore, push: @escaping (FeedRoute) -> Void) {
        self.panel = panel
        self.store = store
        self.push = push
        _postList = State(initialValue: PostList(panel: panel))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { fieldFocused = true }
        .sheet(item: $replyTarget) { target in
            ReplySheet(model: ReplyModel(post: target, store: store)) { replyTarget = nil }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(panel.target.displayName)", text: $query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            if searching { ProgressView().controlSize(.small).scaleEffect(0.7) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            message(errorMessage, systemImage: "exclamationmark.triangle")
        } else if results.isEmpty {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 && !searching {
                message("No results for “\(trimmed)”", systemImage: "magnifyingglass")
            } else {
                message("Search for people and posts", systemImage: "magnifyingglass")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !results.accounts.isEmpty {
                        sectionHeader("People")
                        ForEach(results.accounts) { profile in
                            ProfileRowView(profile: profile) {
                                push(.profile(ProfileRef(id: profile.id, handle: profile.handle,
                                                         name: profile.name, avatar: profile.avatarURL)))
                            }
                        }
                    }
                    if !postList.posts.isEmpty {
                        sectionHeader("Posts")
                        ForEach(postList.posts) { post in postRow(post) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.rowPaddingH).padding(.top, 10).padding(.bottom, 3)
    }

    private func postRow(_ row: FeedPost) -> some View {
        FeedPostView(
            post: row,
            accent: accent,
            onReply: { replyTarget = row },
            onLike: { postList.toggleLike(row) },
            onRepost: { postList.toggleRepost(row) },
            onOpen: { panel.openInBrowser(row) },
            onOpenProfile: { push(.profile(row.profileRef())) },
            onOpenURL: { panel.openLink($0, push: push) },
            isMine: panel.isMine(row),
            onBookmark: { postList.setBookmarked(!row.isBookmarked, on: row) },
            onDelete: { postList.delete(row) },
            onPin: { postList.setPinned(!row.isPinned, on: row) },
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
            onEdit: postEditActions(for: row, panel, onUpdated: { postList.replace($0) }),
            onCopyLink: { panel.copyLink(row) })
    }

    private func message(_ text: String, systemImage: String) -> some View {
        EmptyStateView(text: text, systemImage: systemImage)
    }

    /// Debounce: cancel any pending search and run a new one ~300ms after typing stops.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = SearchResults(); postList.posts = []; searching = false; errorMessage = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await runSearch(trimmed)
        }
    }

    private func runSearch(_ trimmed: String) async {
        searching = true
        errorMessage = nil
        // Only the search for the current query owns the spinner/error/results: a
        // superseded search must not clear a newer one's spinner or replace the
        // current UI with its stale success or failure.
        defer { if isCurrent(trimmed) { searching = false } }
        do {
            let found = try await panel.search(trimmed)
            guard isCurrent(trimmed) else { return }
            results = found
            postList.posts = found.posts
        } catch {
            guard isCurrent(trimmed) else { return }
            errorMessage = error.userMessage
        }
    }

    private func isCurrent(_ trimmed: String) -> Bool {
        trimmed == query.trimmingCharacters(in: .whitespaces)
    }
}
