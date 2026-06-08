import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class FeedPanelModel {
    let target: PostTarget
    var kind: FeedKind = .home
    var posts: [FeedPost] = []
    var isLoading = false
    var errorMessage: String?      // shown only when the feed is empty
    var actionError: String?       // transient banner for failed likes/reposts
    var needsCredentials = false
    var notifications: [FeedNotification] = []
    var conversations: [Conversation] = []
    var unreadCount = 0
    private(set) var scrollToTopToken = 0   // bumped on each user-initiated refresh

    private let store: AccountStore
    private var service: FeedService?
    private var serviceTask: Task<FeedService, Error>?
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var unreadTask: Task<Void, Never>?
    private var mutating: Set<String> = []   // post ids with an in-flight like/repost
    private let pollInterval: UInt64 = 60_000_000_000

    init(target: PostTarget, store: AccountStore) {
        self.target = target
        self.store = store
    }

    private var hasCredentials: Bool {
        target == .mastodon ? store.hasMastodon : store.hasBluesky
    }

    /// (Re)start the panel. Drops any cached service so credential changes take effect.
    func start() {
        service = nil
        serviceTask?.cancel()
        serviceTask = nil
        guard hasCredentials else { needsCredentials = true; return }
        needsCredentials = false
        enqueueLoad(reset: true)
        refreshUnreadCount()
        startPolling()
        startLiveUpdates()
    }

    /// Subscribe to the platform's live stream (Mastodon); each signal refreshes the
    /// current feed. enqueueLoad supersedes in-flight loads, so bursts coalesce.
    private func startLiveUpdates() {
        liveTask?.cancel()
        guard target == .mastodon else { return }   // only Mastodon has a usable user stream
        liveTask = Task { [weak self] in
            var backoff: UInt64 = 2_000_000_000
            while !Task.isCancelled {
                guard let self else { break }
                if let service = try? await self.resolveService(),
                   let stream = await service.liveUpdates() {
                    backoff = 2_000_000_000   // reset after a successful connection
                    for await _ in stream {
                        if Task.isCancelled { break }   // a cancelled stream mustn't keep driving loads
                        if NSApplication.shared.isActive {
                            self.enqueueLoad(reset: false)
                            self.refreshUnreadCount()
                        }
                    }
                }
                // Stream ended (socket dropped) or failed to open — back off and retry.
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: backoff)
                backoff = min(backoff * 2, 60_000_000_000)
            }
        }
    }

    func switchTo(_ newKind: FeedKind) {
        guard newKind != kind else { return }
        kind = newKind
        posts = []
        notifications = []
        conversations = []
        errorMessage = nil
        enqueueLoad(reset: true)
        refreshUnreadCount()   // refresh the badge when leaving the notifications tab
    }

    func refresh() {
        // A refresh must not repurpose the first-run `needsCredentials` flag or it
        // could blank an already-populated panel.
        guard hasCredentials else { return }
        if pollTask == nil { startPolling() }
        scrollToTopToken += 1
        enqueueLoad(reset: false)
    }

    /// Start a load, superseding any in-flight one (so a user action isn't dropped
    /// by a slow background poll).
    private func enqueueLoad(reset: Bool) {
        loadTask?.cancel()
        loadTask = Task { await load(reset: reset) }
    }

    private func load(reset: Bool) async {
        guard hasCredentials else { needsCredentials = true; return }
        if Task.isCancelled { return }
        needsCredentials = false
        isLoading = true
        // A superseded load must not clear the spinner the live load owns.
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let svc = try await resolveService()
            if kind == .notifications {
                let fetched = try await svc.notifications()
                if Task.isCancelled { return }
                errorMessage = nil
                notifications = fetched
                try? await svc.markNotificationsRead(upTo: fetched.first?.id)
                unreadCount = 0
            } else if kind == .messages {
                let fetched = try await svc.conversations()
                if Task.isCancelled { return }
                errorMessage = nil
                conversations = fetched
            } else {
                let fetched = try await svc.loadFeed(kind)
                if Task.isCancelled { return }   // a newer load superseded this one
                errorMessage = nil
                posts = reset
                    ? fetched
                    : FeedMerge.merge(existing: posts, fetched: fetched, preservingIDs: mutating)
            }
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.userMessage
        }
    }

    /// Refresh the unread-notification badge in the background (does not disturb the feed).
    func refreshUnreadCount() {
        guard hasCredentials, kind != .notifications else { return }
        unreadTask?.cancel()
        unreadTask = Task {
            if let svc = try? await resolveService(),
               let count = try? await svc.unreadNotificationCount(),
               !Task.isCancelled,
               kind != .notifications {   // re-check: don't overwrite a just-cleared count
                unreadCount = count
            }
        }
    }

    private func resolveService() async throws -> FeedService {
        if let service { return service }
        // Dedup concurrent callers (load + poll + live + badge all fire on start)
        // so they share one client build instead of each authenticating separately.
        if let serviceTask { return try await serviceTask.value }
        let task = Task { try await FeedServiceFactory.make(for: target, store: store) }
        serviceTask = task
        defer { serviceTask = nil }
        let svc = try await task.value
        service = svc
        return svc
    }

    func toggleLike(_ post: FeedPost) {
        mutate(post, optimistic: {
            $0.isLiked.toggle()
            $0.likeCount = max(0, $0.likeCount + ($0.isLiked ? 1 : -1))
        }) { svc, p in
            try await svc.setLiked(p.isLiked, on: p)
        }
    }

    func toggleRepost(_ post: FeedPost) {
        mutate(post, optimistic: {
            $0.isReposted.toggle()
            $0.repostCount = max(0, $0.repostCount + ($0.isReposted ? 1 : -1))
        }) { svc, p in
            try await svc.setReposted(p.isReposted, on: p)
        }
    }

    func openInBrowser(_ post: FeedPost) {
        guard let url = post.webURL else { return }
        open(url)
    }

    /// The single sink for handing a URL to the system. Rejects any non-web scheme
    /// so a malicious post can't open a `file://` or custom-scheme URL.
    func open(_ url: URL) {
        guard WebLink.isOpenable(url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open a tapped body link: profile/mention links push an in-app profile route;
    /// everything else (articles, hashtags, unresolvable profiles) opens in the browser.
    func openLink(_ url: URL, push: @escaping (FeedRoute) -> Void) {
        guard isProfileLink(url) else { open(url); return }
        Task {
            if let ref = await profileRef(forURL: url) { push(.profile(ref)) } else { open(url) }
        }
    }

    /// Cheap, sync check so non-profile links open in the browser without a network round-trip.
    private func isProfileLink(_ url: URL) -> Bool {
        switch target {
        case .mastodon: return ProfileLink.isMastodonProfileURL(url)
        case .bluesky: return ProfileLink.blueskyID(from: url) != nil
        }
    }

    private func profileRef(forURL url: URL) async -> ProfileRef? {
        guard let profile = try? await resolveService().profile(forURL: url) else { return nil }
        return ProfileRef(id: profile.id, handle: profile.handle, name: profile.name, avatar: profile.avatarURL)
    }

    /// Fetch the surrounding thread (ancestors + replies) for the detail view.
    func thread(of post: FeedPost) async -> PostThread {
        do {
            let svc = try await resolveService()
            return try await svc.thread(of: post)
        } catch {
            return PostThread(ancestors: [], descendants: [])
        }
    }

    func profile(id: String) async -> Profile? {
        try? await resolveService().profile(id: id)
    }

    func myProfile() async -> Profile? {
        try? await resolveService().myProfile()
    }

    func authorPosts(id: String) async -> [FeedPost] {
        (try? await resolveService().authorPosts(id: id)) ?? []
    }

    func relationship(with id: String) async -> AccountRelationship {
        (try? await resolveService().relationship(with: id)) ?? AccountRelationship()
    }

    func setFollowing(_ following: Bool, for id: String,
                      current: AccountRelationship) async throws -> AccountRelationship {
        try await resolveService().setFollowing(following, for: id, current: current)
    }

    func setMuted(_ muted: Bool, for id: String,
                  current: AccountRelationship) async throws -> AccountRelationship {
        try await resolveService().setMuted(muted, for: id, current: current)
    }

    func setBlocked(_ blocked: Bool, for id: String,
                    current: AccountRelationship) async throws -> AccountRelationship {
        try await resolveService().setBlocked(blocked, for: id, current: current)
    }

    func followers(of id: String) async -> [Profile] {
        (try? await resolveService().followers(of: id)) ?? []
    }

    func following(of id: String) async -> [Profile] {
        (try? await resolveService().following(of: id)) ?? []
    }

    /// Whether a post was authored by the signed-in user (controls delete/pin actions).
    func isMine(_ post: FeedPost) -> Bool {
        let mine = target == .mastodon ? store.mastodonUsername : store.blueskyHandle
        return !mine.isEmpty && post.authorHandle.lowercased() == "@\(mine.lowercased())"
    }

    func deletePost(_ post: FeedPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else {
            // Not in this timeline (thread/profile lists remove their own row and
            // call serviceDeletePost); just perform the server-side delete.
            Task {
                do { try await serviceDeletePost(post) }
                catch { showActionError(error.userMessage) }
            }
            return
        }
        let removed = posts.remove(at: index)
        Task {
            do { try await serviceDeletePost(post) }
            catch {
                if !posts.contains(where: { $0.id == post.id }) {
                    posts.insert(removed, at: min(index, posts.count))
                }
                showActionError(error.userMessage)
            }
        }
    }

    /// Server-side delete only — used by thread/profile lists that manage their
    /// own optimistic row removal and rollback.
    func serviceDeletePost(_ post: FeedPost) async throws {
        try await resolveService().deletePost(post)
    }

    /// Surface a transient error banner from a list outside this panel's timeline.
    func reportActionError(_ message: String) {
        showActionError(message)
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) {
        updatePost(post.id) { $0.isBookmarked = bookmarked }
        Task {
            do {
                let updated = try await resolveService().setBookmarked(bookmarked, on: post)
                updatePost(post.id) { $0.isBookmarked = updated.isBookmarked }
            } catch {
                updatePost(post.id) { $0.isBookmarked = !bookmarked }
                showActionError(error.userMessage)
            }
        }
    }

    func setPinned(_ pinned: Bool, on post: FeedPost) {
        Task {
            do {
                let updated = try await resolveService().setPinned(pinned, on: post)
                updatePost(post.id) { $0.isPinned = updated.isPinned }
            } catch { showActionError(error.userMessage) }
        }
    }

    func messages(in conversationID: String) async -> [DirectMessage] {
        (try? await resolveService().messages(in: conversationID)) ?? []
    }

    func sendMessage(_ text: String, to conversationID: String) async throws {
        try await resolveService().sendMessage(text, to: conversationID)
    }

    /// Refresh the conversation list (last-message previews, ordering) after activity.
    func reloadConversations() async {
        if let fetched = try? await resolveService().conversations() { conversations = fetched }
    }

    /// Optimistically clear a conversation's unread dot when it's opened.
    func markConversationRead(_ id: String) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].unreadCount = 0
        }
    }

    func likedBy(_ post: FeedPost) async -> [Profile] {
        (try? await resolveService().likedBy(post)) ?? []
    }

    func repostedBy(_ post: FeedPost) async -> [Profile] {
        (try? await resolveService().repostedBy(post)) ?? []
    }

    private func updatePost(_ id: String, _ mutate: (inout FeedPost) -> Void) {
        if let index = posts.firstIndex(where: { $0.id == id }) { mutate(&posts[index]) }
    }

    /// Service-backed like/repost for posts not held in this panel's timeline
    /// (used by thread and profile lists).
    func serviceSetLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        try await resolveService().setLiked(liked, on: post)
    }

    func serviceSetReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        try await resolveService().setReposted(reposted, on: post)
    }

    /// Flip the UI immediately, call the service, reconcile or revert on failure.
    /// Ignores a second toggle for the same post while one is already in flight.
    private func mutate(_ post: FeedPost,
                        optimistic: (inout FeedPost) -> Void,
                        action: @escaping (FeedService, FeedPost) async throws -> FeedPost) {
        guard !mutating.contains(post.id),
              let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        mutating.insert(post.id)
        let original = posts[index]
        var optimisticPost = original
        optimistic(&optimisticPost)
        posts[index] = optimisticPost
        Task {
            defer { mutating.remove(post.id) }
            do {
                let svc = try await resolveService()
                let updated = try await action(svc, optimisticPost)
                // Only reconcile if a reset-load hasn't replaced this post meanwhile.
                if let i = posts.firstIndex(where: { $0.id == post.id }), posts[i] == optimisticPost {
                    posts[i] = updated
                }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }), posts[i] == optimisticPost {
                    posts[i] = original
                }
                showActionError(error.userMessage)
            }
        }
    }

    private func showActionError(_ message: String) {
        actionError = message
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if actionError == message { actionError = nil }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 60_000_000_000)
                if Task.isCancelled { break }
                // Only poll while the app is active, to avoid background churn.
                if NSApplication.shared.isActive {
                    self?.enqueueLoad(reset: false)
                    self?.refreshUnreadCount()
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        loadTask?.cancel(); loadTask = nil
        liveTask?.cancel(); liveTask = nil
        unreadTask?.cancel(); unreadTask = nil
        isLoading = false
    }
}
