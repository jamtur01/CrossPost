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
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    // Monotonic guard: each (re)scheduled search gets a generation, and only the
    // newest may apply its results — a string compare can't tell a stale response
    // for an identical retyped query from the current one.
    @State private var searchGeneration = 0
    @FocusState private var fieldFocused: Bool

    private var accent: Color {
        panel.target.accent
    }

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
        .onDisappear { stop() }
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
            if isSearching {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
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
            if trimmed.count >= 2 && !isSearching {
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
                                push(.profile(profile.profileRef()))
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
        FeedRow(post: row, host: postList, panel: panel, accent: accent,
                push: push, onReply: { replyTarget = $0 })
    }

    private func message(_ text: String, systemImage: String) -> some View {
        EmptyStateView(text: text, systemImage: systemImage)
    }

    private func stop() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        postList.invalidateOptimisticMutations()
    }

    /// Debounce: cancel any pending search and run a new one ~300ms after typing stops.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        searchGeneration += 1
        postList.invalidateOptimisticMutations()
        results = SearchResults()
        postList.posts = []
        errorMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            isSearching = false
            return
        }
        isSearching = true
        let generation = searchGeneration
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled {
                return
            }
            await runSearch(trimmed, generation: generation)
        }
    }

    private func runSearch(_ trimmed: String, generation: Int) async {
        isSearching = true
        errorMessage = nil
        // Only the newest scheduled search owns the spinner/error/results: a
        // superseded search must not clear a newer one's spinner or replace the
        // current UI with its stale success or failure.
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }
        do {
            let found = try await panel.search(trimmed)
            guard generation == searchGeneration else { return }
            results = found
            postList.posts = found.posts
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.userMessage
        }
    }
}
