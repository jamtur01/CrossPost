import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class FeedPanelModel: OptimisticPostHost {
    let target: PostTarget
    var kind: FeedKind = .home
    var posts: [FeedPost] = []
    var isLoading = false
    var errorMessage: String? // shown only when the feed is empty
    var actionError: String? // transient banner for failed likes/reposts
    var needsCredentials = false
    var notifications: [FeedNotification] = []
    /// Actor ids the signed-in user follows, resolved in batch after each
    /// notifications load so rows can show real follow state immediately.
    var followedActorIDs: Set<String> = []
    var conversations: [Conversation] = []
    var unreadCount = 0
    var scrollToTopToken = 0 // bumped on each user-initiated refresh

    let store: AccountStore
    let makeService: @MainActor (PostTarget, AccountStore) async throws -> FeedService
    @ObservationIgnored var applicationIsActive: @MainActor () -> Bool = {
        NSApplication.shared.isActive
    }

    var service: FeedService?
    struct ServiceResolution {
        let id: UUID
        let task: Task<FeedService, Error>
    }

    var serviceResolution: ServiceResolution?
    var serviceResolutionIsActive = false
    var loadTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var liveTask: Task<Void, Never>?
    @ObservationIgnored var liveTaskID: UUID?
    var unreadTask: Task<Void, Never>?
    var followStateTask: Task<Void, Never>?
    @ObservationIgnored var followStateTaskID: UUID?
    @ObservationIgnored var followStateGenerations: [String: UInt] = [:]
    var profileLinkTask: Task<Void, Never>?
    @ObservationIgnored var profileLinkGeneration: UInt = 0
    private var actionErrorTask: Task<Void, Never>?
    var pendingLoad: LoadRequest?
    var activeLoadID: UUID?
    var unreadRefreshPending = false
    var unreadTaskID: UUID?
    var isLiveConnected = false
    var inFlight: Set<String> = [] // post ids with an in-flight like/repost/delete/etc.
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
    @ObservationIgnored var pollSleep: @MainActor (UInt64) async -> Void = {
        try? await Task.sleep(nanoseconds: $0)
    }

    @ObservationIgnored var liveTaskDidExit: @MainActor () -> Void = {}

    init(
        target: PostTarget,
        store: AccountStore,
        makeService: @escaping @MainActor (PostTarget, AccountStore) async throws -> FeedService
            = FeedServiceFactory.make
    ) {
        self.target = target
        self.store = store
        self.makeService = makeService
    }

    var hasCredentials: Bool {
        target == .mastodon ? store.hasMastodon : store.hasBluesky
    }

    /// (Re)start the panel. Drops any cached service so credential changes take effect,
    /// and cancels every running task first so a cleared or invalidated account cannot
    /// leave the old account's poll, live, unread, or load work running.
    func start() {
        restart(clearingContent: false)
    }

    /// A credential change also removes account-owned snapshots synchronously, so
    /// old rows cannot send mutations through the replacement account's service.
    func restartAfterCredentialsChange() {
        restart(clearingContent: true)
    }

    private func restart(clearingContent: Bool) {
        stop()
        service = nil
        if clearingContent {
            posts = []
            notifications = []
            conversations = []
            followedActorIDs = []
            unreadCount = 0
        }
        guard hasCredentials else {
            needsCredentials = true
            return
        }
        serviceResolutionIsActive = true
        needsCredentials = false
        enqueueLoad(reset: true, userInitiated: false)
        refreshUnreadCount()
        startPolling()
        startLiveUpdates()
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
            if self.actionErrorToken == token {
                self.actionError = nil
            }
        }
    }

    /// Dismiss the transient error banner immediately (tapping it).
    func dismissActionError() {
        actionErrorTask?.cancel()
        actionErrorTask = nil
        actionError = nil
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // A deallocated model means nobody owns this loop any more — end it
                // rather than sleeping forever as a zombie.
                guard let interval = self?.pollInterval,
                      let pollSleep = self?.pollSleep else { break }
                await pollSleep(interval)
                if Task.isCancelled {
                    break
                }
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
        liveTaskID = nil
        liveTask?.cancel(); liveTask = nil
        isLiveConnected = false
        cancelUnreadRefresh()
        cancelFollowStateLookup()
        invalidateProfileLinkLookup()
        actionErrorTask?.cancel()
        actionErrorTask = nil
        actionErrorToken = UUID()
        actionError = nil
        serviceResolutionIsActive = false
        serviceResolution?.task.cancel(); serviceResolution = nil
    }
}
