import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class FeedPanelModel: OptimisticPostHost {
    let target: PostTarget
    var kind: FeedKind = .home
    var posts: [FeedPost] = []
    var isLoading = false
    var errorMessage: String?      // shown only when the feed is empty
    var actionError: String?       // transient banner for failed likes/reposts
    var needsCredentials = false
    var notifications: [FeedNotification] = []
    /// Actor ids the signed-in user follows, resolved in batch after each
    /// notifications load so rows can show real follow state immediately.
    private(set) var followedActorIDs: Set<String> = []
    var conversations: [Conversation] = []
    var unreadCount = 0
    private(set) var scrollToTopToken = 0   // bumped on each user-initiated refresh

    private let store: AccountStore
    private let makeService: @MainActor (PostTarget, AccountStore) async throws -> FeedService
    private var service: FeedService?
    private var serviceTask: Task<FeedService, Error>?
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var unreadTask: Task<Void, Never>?
    private var followStateTask: Task<Void, Never>?
    var inFlight: Set<String> = []   // post ids with an in-flight like/repost/etc.
    // 30s active-only poll. Well within both platforms' limits: Mastodon allows 300
    // requests / 5 min per account (~8/min here, well under), Bluesky 3000 / 5 min per
    // IP. Bluesky has no live stream, so this poll is its only passive freshness path.
    private let pollInterval: UInt64 = 30_000_000_000

    init(target: PostTarget, store: AccountStore,
         makeService: @escaping @MainActor (PostTarget, AccountStore) async throws -> FeedService
             = FeedServiceFactory.make) {
        self.target = target
        self.store = store
        self.makeService = makeService
    }

    private var hasCredentials: Bool {
        target == .mastodon ? store.hasMastodon : store.hasBluesky
    }

    /// (Re)start the panel. Drops any cached service so credential changes take effect,
    /// and cancels every running task first so a credential change that clears or
    /// invalidates the account can't leave the old account's poll/live/unread/load
    /// tasks running (the live stream would otherwise retry-loop forever).
    func start() {
        stop()
        service = nil
        guard hasCredentials else { needsCredentials = true; return }
        needsCredentials = false
        enqueueLoad(reset: true, userInitiated: false)
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
                            self.enqueueLoad(reset: false, userInitiated: false)
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
        enqueueLoad(reset: true, userInitiated: false)
        refreshUnreadCount()   // refresh the badge when leaving the notifications tab
    }

    func refresh() {
        // A refresh must not repurpose the first-run `needsCredentials` flag or it
        // could blank an already-populated panel.
        guard hasCredentials else { return }
        if pollTask == nil { startPolling() }
        scrollToTopToken += 1
        enqueueLoad(reset: false, userInitiated: true)
        refreshUnreadCount()   // a manual refresh must update the badge too, not just the feed
    }

    /// Foreground wake (the app was re-activated): silently catch the feed and the
    /// unread badge up — the same work a poll tick does, but immediately rather than
    /// waiting up to a full interval, and without the scroll-to-top of a user refresh.
    /// Bluesky has no live stream, so without this its badge only moves on the 60s poll.
    func wake() {
        guard hasCredentials else { return }
        if pollTask == nil { startPolling() }
        enqueueLoad(reset: false, userInitiated: false)
        refreshUnreadCount()
    }

    /// Start a load, superseding any in-flight one (so a user action isn't dropped
    /// by a slow background poll). `userInitiated` distinguishes a refresh the user
    /// asked for (worth a transient error banner) from a silent background poll.
    private func enqueueLoad(reset: Bool, userInitiated: Bool) {
        loadTask?.cancel()
        loadTask = Task { await load(reset: reset, userInitiated: userInitiated) }
    }

    private func load(reset: Bool, userInitiated: Bool) async {
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
                refreshFollowStates(for: fetched, service: svc)
                // Only clear the badge once the server confirms the read; a failed
                // mark must not falsely zero it. Cancel any in-flight unread fetch so
                // a stale count can't resurrect the badge after we clear it.
                if (try? await svc.markNotificationsRead(upTo: fetched.first)) != nil {
                    unreadTask?.cancel()
                    unreadCount = 0
                }
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
                    : FeedMerge.merge(existing: posts, fetched: fetched, preservingIDs: inFlight)
            }
        } catch {
            if Task.isCancelled { return }
            if currentCollectionIsEmpty {
                // Nothing to show: a sticky explanation in the empty state is right.
                errorMessage = error.userMessage
            } else if userInitiated {
                // We already have content; the user asked for a refresh, so give brief
                // feedback that auto-dismisses instead of a banner that sticks forever.
                reportError(error.userMessage)
            }
            // A background poll/live failure with content present stays silent — the
            // stale content stands and the next poll will quietly recover.
        }
    }

    /// Whether the collection backing the current tab has nothing in it, used to
    /// decide between a sticky empty-state error and a transient refresh error.
    private var currentCollectionIsEmpty: Bool {
        switch kind {
        case .notifications: return notifications.isEmpty
        case .messages: return conversations.isEmpty
        case .home: return posts.isEmpty
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
        let task = Task { try await makeService(target, store) }
        serviceTask = task
        do {
            let svc = try await task.value
            // start()/stop() cancel this task when credentials change or the panel
            // tears down; a build that finished anyway must not be installed, or a
            // client for the old account would serve every later call.
            guard !task.isCancelled else { throw CancellationError() }
            serviceTask = nil
            service = svc
            return svc
        } catch {
            // On cancellation the canceller already cleared (and may have replaced)
            // serviceTask — only a plain failure should clear it for retry.
            if !task.isCancelled { serviceTask = nil }
            throw error
        }
    }

    func openInBrowser(_ post: FeedPost) {
        guard let url = post.webURL else { return }
        open(url)
    }

    /// Copy the post's web URL to the clipboard. Returns whether a URL was copied.
    @discardableResult
    func copyLink(_ post: FeedPost) -> Bool {
        guard let url = post.webURL else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        return true
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
        return profile.profileRef()
    }

    /// Fetch the surrounding thread (ancestors + replies) for the detail view.
    // These detail-view fetches propagate errors so the views can show a real
    // error state with retry, rather than an empty pane that hides a failure.

    func thread(of post: FeedPost) async throws -> PostThread {
        try await resolveService().thread(of: post)
    }

    func profile(id: String) async throws -> Profile {
        try await resolveService().profile(id: id)
    }

    func myProfile() async throws -> Profile {
        try await resolveService().myProfile()
    }

    func authorPosts(id: String) async throws -> [FeedPost] {
        try await resolveService().authorPosts(id: id)
    }

    func pinnedPosts(id: String) async throws -> [FeedPost] {
        try await resolveService().pinnedPosts(of: id)
    }

    func search(_ query: String) async throws -> SearchResults {
        try await resolveService().search(query)
    }

    func bookmarkedPosts() async throws -> [FeedPost] {
        try await resolveService().bookmarkedPosts()
    }

    func likedPosts() async throws -> [FeedPost] {
        try await resolveService().likedPosts()
    }

    func editableSource(of post: FeedPost) async throws -> EditableSource {
        try await resolveService().editableSource(of: post)
    }

    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        let updated = try await resolveService().edit(post: post, text: text, spoiler: spoiler)
        // Update this panel's timeline row immediately; also refresh so the rest of
        // the platform's surfaces (and counts) catch up.
        updatePost(post.id) { $0 = updated }
        NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                        userInfo: [crossPostTargetsKey: Set([post.target])])
        return updated
    }

    func quote(post: FeedPost, text: String, visibility: PostVisibility) async throws -> PostedItem {
        let item = try await resolveService().quote(post: post, text: text, visibility: visibility)
        // Refresh this platform's feed so the new quote shows up.
        NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                        userInfo: [crossPostTargetsKey: Set([post.target])])
        return item
    }

    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        try await resolveService().report(post: post, reason: reason, comment: comment)
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        try await resolveService().report(accountID: id, reason: reason, comment: comment)
    }

    func relationship(with id: String) async -> AccountRelationship {
        (try? await resolveService().relationship(with: id)) ?? AccountRelationship()
    }

    func setFollowing(_ following: Bool, for id: String,
                      current: AccountRelationship) async throws -> AccountRelationship {
        // A user action wins over any in-flight batch resolve: cancel it so a stale
        // snapshot can't land afterward and revert the change we're about to make.
        followStateTask?.cancel()
        let updated = try await resolveService().setFollowing(following, for: id, current: current)
        // Keep the shared follow set in sync so every row for this actor updates,
        // including after a follow/unfollow made from a profile view.
        if updated.isFollowing { followedActorIDs.insert(id) } else { followedActorIDs.remove(id) }
        return updated
    }

    /// Whether the signed-in user follows this actor, per the latest batch resolve.
    func isFollowing(_ actorID: String) -> Bool { followedActorIDs.contains(actorID) }

    /// One-way follow used by notification rows: resolves the relationship first and
    /// follows only if needed, so a stale "Follow" label can never unfollow anyone.
    /// Unfollow lives on the profile view.
    func follow(actorID: String) async {
        let current = await relationship(with: actorID)
        if current.isFollowing { followedActorIDs.insert(actorID); return }
        do { _ = try await setFollowing(true, for: actorID, current: current) }
        catch { reportError(error.userMessage) }
    }

    /// Resolve follow state for a page of notification actors in one round-trip
    /// (Bluesky pages by 25), so rows show the real state instead of a default.
    /// Merges the result into the shared set rather than replacing it, so a follow
    /// the user just made on an actor outside this page isn't dropped.
    private func refreshFollowStates(for fetched: [FeedNotification], service: FeedService) {
        let ids = Set(fetched.map(\.actorID)).subtracting([""])
        followStateTask?.cancel()
        guard !ids.isEmpty else { return }
        followStateTask = Task {
            guard let relationships = try? await service.relationships(with: Array(ids)),
                  !Task.isCancelled else { return }
            for (id, relationship) in relationships {
                if relationship.isFollowing { followedActorIDs.insert(id) }
                else { followedActorIDs.remove(id) }
            }
        }
    }

    func setMuted(_ muted: Bool, for id: String,
                  current: AccountRelationship) async throws -> AccountRelationship {
        try await resolveService().setMuted(muted, for: id, current: current)
    }

    func setBlocked(_ blocked: Bool, for id: String,
                    current: AccountRelationship) async throws -> AccountRelationship {
        try await resolveService().setBlocked(blocked, for: id, current: current)
    }

    func followers(of id: String) async throws -> [Profile] {
        try await resolveService().followers(of: id)
    }

    func following(of id: String) async throws -> [Profile] {
        try await resolveService().following(of: id)
    }

    /// Whether a post was authored by the signed-in user (controls delete/pin actions).
    func isMine(_ post: FeedPost) -> Bool {
        let mine = target == .mastodon ? store.mastodonUsername : store.blueskyHandle
        return !mine.isEmpty && post.authorHandle.lowercased() == "@\(mine.lowercased())"
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

    func likedBy(_ post: FeedPost) async throws -> [Profile] {
        try await resolveService().likedBy(post)
    }

    func repostedBy(_ post: FeedPost) async throws -> [Profile] {
        try await resolveService().repostedBy(post)
    }

    private func updatePost(_ id: String, _ mutate: (inout FeedPost) -> Void) {
        if let index = posts.firstIndex(where: { $0.id == id }) { mutate(&posts[index]) }
    }

    // MARK: OptimisticPostHost — the remote calls the shared engine drives.
    // Also the service bridge PostList uses for its own rows.

    func remoteSetLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        try await resolveService().setLiked(liked, on: post)
    }
    func remoteSetReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        try await resolveService().setReposted(reposted, on: post)
    }
    func remoteSetBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        try await resolveService().setBookmarked(bookmarked, on: post)
    }
    func remoteSetPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost {
        try await resolveService().setPinned(pinned, on: post)
    }
    func remoteDelete(_ post: FeedPost) async throws {
        try await resolveService().deletePost(post)
    }

    /// Surface a transient error banner (failed like/repost/follow/…) that
    /// auto-dismisses. The shared engine and external lists both report through this.
    func reportError(_ message: String) {
        actionError = message
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if actionError == message { actionError = nil }
        }
    }

    /// Dismiss the transient error banner immediately (tapping it).
    func dismissActionError() { actionError = nil }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 60_000_000_000)
                if Task.isCancelled { break }
                // Only poll while the app is active, to avoid background churn.
                if NSApplication.shared.isActive {
                    self?.enqueueLoad(reset: false, userInitiated: false)
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
        followStateTask?.cancel(); followStateTask = nil
        serviceTask?.cancel(); serviceTask = nil
        isLoading = false
    }
}
