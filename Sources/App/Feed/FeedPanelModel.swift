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
    @ObservationIgnored var applicationIsActive: @MainActor () -> Bool = {
        NSApplication.shared.isActive
    }
    private var service: FeedService?
    private var serviceTask: Task<FeedService, Error>?
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var unreadTask: Task<Void, Never>?
    private var followStateTask: Task<Void, Never>?
    private var profileLinkTask: Task<Void, Never>?
    @ObservationIgnored private var profileLinkGeneration: UInt = 0
    private var actionErrorTask: Task<Void, Never>?
    private var pendingLoad: LoadRequest?
    private var activeLoadID: UUID?
    private var unreadRefreshPending = false
    private var unreadTaskID: UUID?
    private var isLiveConnected = false
    var inFlight: Set<String> = []   // post ids with an in-flight like/repost/delete/etc.
    @ObservationIgnored var mutationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var mutationGeneration: UInt = 0
    /// Identity of the banner the running dismiss timer belongs to. Keyed by token,
    /// not message text, so a renewed identical banner gets a fresh timeout instead
    /// of being dismissed early by the previous banner's timer.
    @ObservationIgnored private var actionErrorToken = UUID()
    /// Injectable for tests only — the real 4s banner timeout would make the
    /// renewed-banner timer test take multiple seconds.
    @ObservationIgnored var actionErrorDismissDelay: UInt64 = 4_000_000_000
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

    /// Subscribe to Mastodon's live stream. Each event requests a refresh; the load
    /// coordinator permits one active request and one trailing request for a burst.
    private func startLiveUpdates() {
        liveTask?.cancel()
        guard target == .mastodon else { return }
        liveTask = Task { [weak self] in
            var backoff: UInt64 = 2_000_000_000
            while !Task.isCancelled {
                var stream: AsyncStream<Void>?
                if let self, let service = try? await self.resolveService() {
                    stream = await service.liveUpdates()
                }
                if let stream {
                    self?.isLiveConnected = true
                    backoff = 2_000_000_000
                    for await _ in stream {
                        if Task.isCancelled { break }
                        guard let self else { break }
                        if self.applicationIsActive() {
                            self.enqueueLoad(reset: false, userInitiated: false)
                            self.refreshUnreadCount()
                        }
                    }
                    self?.isLiveConnected = false
                }
                if Task.isCancelled || self == nil { break }
                let delay = "\(backoff / 1_000_000_000)s"
                Log.feed.debug(
                    "mastodon live stream dropped; reconnecting in \(delay, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: backoff)
                backoff = min(backoff * 2, 60_000_000_000)
            }
        }
    }

    private struct LoadRequest {
        var reset: Bool
        var userInitiated: Bool

        mutating func merge(_ newer: LoadRequest) {
            reset = reset || newer.reset
            userInitiated = userInitiated || newer.userInitiated
        }
    }
    func switchTo(_ newKind: FeedKind) {
        guard newKind != kind else { return }
        invalidateOptimisticMutations()
        invalidateProfileLinkLookup()
        cancelUnreadRefresh()
        cancelLoads()
        kind = newKind
        posts = []
        notifications = []
        conversations = []
        errorMessage = nil
        enqueueLoad(reset: true, userInitiated: false)
        refreshUnreadCount()
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
    /// Bluesky has no live stream, so without this its badge only moves on the 30s poll.
    func wake() {
        guard hasCredentials else { return }
        if pollTask == nil { startPolling() }
        enqueueLoad(reset: false, userInitiated: false)
        refreshUnreadCount()
    }

    /// Queue a load without allowing refresh bursts to fan out into parallel requests.
    /// One active request may be followed by one merged trailing request.
    private func enqueueLoad(reset: Bool, userInitiated: Bool) {
        let request = LoadRequest(reset: reset, userInitiated: userInitiated)
        guard loadTask == nil else {
            if pendingLoad == nil {
                pendingLoad = request
            } else {
                pendingLoad?.merge(request)
            }
            return
        }
        startLoad(request)
    }

    private func startLoad(_ request: LoadRequest) {
        let id = UUID()
        activeLoadID = id
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(reset: request.reset, userInitiated: request.userInitiated)
            self.finishLoad(id: id)
        }
    }

    private func finishLoad(id: UUID) {
        guard activeLoadID == id else { return }
        loadTask = nil
        activeLoadID = nil
        if let pendingLoad {
            self.pendingLoad = nil
            startLoad(pendingLoad)
        } else {
            isLoading = false
        }
    }

    private func cancelLoads() {
        loadTask?.cancel()
        loadTask = nil
        activeLoadID = nil
        pendingLoad = nil
        isLoading = false
    }

    private func load(reset: Bool, userInitiated: Bool) async {
        guard hasCredentials else { needsCredentials = true; return }
        if Task.isCancelled { return }
        needsCredentials = false
        do {
            let service = try await resolveService()
            if Task.isCancelled { return }
            switch kind {
            case .notifications:
                try await loadNotifications(from: service)
            case .messages:
                try await loadConversations(from: service)
            case .home:
                try await loadPosts(reset: reset, from: service)
            }
        } catch {
            handleLoadError(error, userInitiated: userInitiated)
        }
    }

    private func loadNotifications(from service: FeedService) async throws {
        let fetched = try await service.notifications()
        if Task.isCancelled { return }
        if errorMessage != nil { errorMessage = nil }
        if notifications != fetched { notifications = fetched }
        refreshFollowStates(for: fetched, service: service)
        guard (try? await service.markNotificationsRead(upTo: fetched.first)) != nil,
              !Task.isCancelled else { return }
        cancelUnreadRefresh()
        if unreadCount != 0 { unreadCount = 0 }
    }

    private func loadConversations(from service: FeedService) async throws {
        let fetched = try await service.conversations()
        if Task.isCancelled { return }
        if errorMessage != nil { errorMessage = nil }
        if conversations != fetched { conversations = fetched }
    }

    private func loadPosts(reset: Bool, from service: FeedService) async throws {
        let fetched = try await service.loadFeed(kind)
        if Task.isCancelled { return }
        if errorMessage != nil { errorMessage = nil }
        let next = reset
            ? fetched
            : FeedMerge.merge(
                existing: posts,
                fetched: fetched,
                preservingIDs: inFlight,
                excludingIDs: inFlight.subtracting(posts.lazy.map(\.id))
            )
        if posts != next { posts = next }
    }

    private func handleLoadError(_ error: Error, userInitiated: Bool) {
        if Task.isCancelled { return }
        if currentCollectionIsEmpty {
            errorMessage = error.userMessage
        } else if userInitiated {
            reportError(error.userMessage)
        }
        let context = "\(target.rawValue) \(kind.rawValue)"
        Log.feed.error("\(context, privacy: .public) load failed: \(error)")
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

    /// Refresh the unread-notification badge without allowing event bursts to fan
    /// out into parallel requests. One active request may have one trailing request.
    func refreshUnreadCount() {
        guard hasCredentials, kind != .notifications else { return }
        guard unreadTask == nil else {
            unreadRefreshPending = true
            return
        }
        let id = UUID()
        unreadTaskID = id
        unreadTask = Task { [weak self] in
            guard let self else { return }
            let service = try? await self.resolveService()
            if Task.isCancelled { return }
            let count = try? await service?.unreadNotificationCount()
            self.finishUnreadRefresh(id: id, count: count)
        }
    }

    private func finishUnreadRefresh(id: UUID, count: Int?) {
        guard unreadTaskID == id else { return }
        unreadTask = nil
        unreadTaskID = nil
        if let count, kind != .notifications, unreadCount != count {
            unreadCount = count
        }
        if unreadRefreshPending {
            unreadRefreshPending = false
            refreshUnreadCount()
        }
    }

    private func cancelUnreadRefresh() {
        unreadTask?.cancel()
        unreadTask = nil
        unreadTaskID = nil
        unreadRefreshPending = false
    }

    func resolveService() async throws -> FeedService {
        if let service { return service }
        // Dedup concurrent callers (load + poll + live + badge all fire on start)
        // so they share one client build instead of each authenticating separately.
        if let serviceTask {
            let resolved = try await serviceTask.value
            guard !serviceTask.isCancelled else { throw CancellationError() }
            return resolved
        }
        let task = Task {
            let resolved = try await makeService(target, store)
            try Task.checkCancellation()
            return resolved
        }
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
        invalidateProfileLinkLookup()
        guard isProfileLink(url) else { open(url); return }
        let generation = profileLinkGeneration
        profileLinkTask = Task { [weak self] in
            guard let self else { return }
            let ref = await self.profileRef(forURL: url)
            guard !Task.isCancelled,
                  self.profileLinkGeneration == generation else { return }
            self.profileLinkTask = nil
            if let ref { push(.profile(ref)) } else { self.open(url) }
        }
    }

    /// Cancel a profile lookup whose navigation destination no longer owns the route.
    func invalidateProfileLinkLookup() {
        profileLinkGeneration += 1
        profileLinkTask?.cancel()
        profileLinkTask = nil
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
        do {
            _ = try await setFollowing(true, for: actorID, current: current)
        } catch {
            reportError(error.userMessage)
        }
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
                if relationship.isFollowing {
                    followedActorIDs.insert(id)
                } else {
                    followedActorIDs.remove(id)
                }
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
        if let fetched = try? await resolveService().conversations(),
           conversations != fetched {
            conversations = fetched
        }
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

    func updatePost(_ id: String, _ mutate: (inout FeedPost) -> Void) {
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
        let token = UUID()
        actionErrorToken = token
        actionErrorTask?.cancel()
        actionErrorTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.actionErrorDismissDelay)
            } catch {
                return
            }
            if self.actionErrorToken == token { self.actionError = nil }
        }
    }

    /// Dismiss the transient error banner immediately (tapping it).
    func dismissActionError() {
        actionErrorTask?.cancel()
        actionErrorTask = nil
        actionError = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // A deallocated model means nobody owns this loop any more — end it
                // rather than sleeping forever as a zombie.
                guard let interval = self?.pollInterval else { break }
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                guard let self else { break }
                if self.applicationIsActive() {
                    if self.target != .mastodon || !self.isLiveConnected {
                        self.enqueueLoad(reset: false, userInitiated: false)
                    }
                    self.refreshUnreadCount()
                }
            }
        }
    }

    func stop() {
        invalidateOptimisticMutations()
        pollTask?.cancel(); pollTask = nil
        cancelLoads()
        liveTask?.cancel(); liveTask = nil
        isLiveConnected = false
        cancelUnreadRefresh()
        followStateTask?.cancel(); followStateTask = nil
        invalidateProfileLinkLookup()
        actionErrorTask?.cancel()
        actionErrorTask = nil
        actionErrorToken = UUID()
        actionError = nil
        serviceTask?.cancel(); serviceTask = nil
    }
}
