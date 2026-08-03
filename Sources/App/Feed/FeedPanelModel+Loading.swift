import Foundation

@MainActor
extension FeedPanelModel {
    struct LoadRequest {
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
        cancelFollowStateLookup()
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
        if pollTask == nil {
            startPolling()
        }
        scrollToTopToken += 1
        enqueueLoad(reset: false, userInitiated: true)
        refreshUnreadCount() // a manual refresh must update the badge too, not just the feed
    }

    /// Foreground wake (the app was re-activated): silently catch the feed and the
    /// unread badge up — the same work a poll tick does, but immediately rather than
    /// waiting up to a full interval, and without the scroll-to-top of a user refresh.
    /// Bluesky has no live stream, so without this its badge only moves on the 30s poll.
    func wake() {
        guard hasCredentials else { return }
        if pollTask == nil {
            startPolling()
        }
        enqueueLoad(reset: false, userInitiated: false)
        refreshUnreadCount()
    }

    /// Queue a load without allowing refresh bursts to fan out into parallel requests.
    /// One active request may be followed by one merged trailing request.
    func enqueueLoad(reset: Bool, userInitiated: Bool) {
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

    func cancelLoads() {
        loadTask?.cancel()
        loadTask = nil
        activeLoadID = nil
        pendingLoad = nil
        isLoading = false
    }

    private func load(reset: Bool, userInitiated: Bool) async {
        guard hasCredentials else { needsCredentials = true; return }
        if Task.isCancelled {
            return
        }
        needsCredentials = false
        do {
            let service = try await resolveService()
            if Task.isCancelled {
                return
            }
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
        if Task.isCancelled {
            return
        }
        if errorMessage != nil {
            errorMessage = nil
        }
        if notifications != fetched {
            notifications = fetched
        }
        refreshFollowStates(for: fetched, service: service)
        do {
            try await service.markNotificationsRead(upTo: fetched.first)
            guard !Task.isCancelled else { return }
            cancelUnreadRefresh()
            if unreadCount != 0 {
                unreadCount = 0
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            reportError("Couldn't mark notifications read. \(error.userMessage)")
            Log.feed.error("marking notifications read failed: \(error)")
        }
    }

    private func loadConversations(from service: FeedService) async throws {
        let fetched = try await service.conversations()
        if Task.isCancelled {
            return
        }
        if errorMessage != nil {
            errorMessage = nil
        }
        if conversations != fetched {
            conversations = fetched
        }
    }

    private func loadPosts(reset: Bool, from service: FeedService) async throws {
        let fetched = try await service.loadFeed(kind)
        if Task.isCancelled {
            return
        }
        if errorMessage != nil {
            errorMessage = nil
        }
        let next = reset
            ? fetched
            : FeedMerge.merge(
                existing: posts,
                fetched: fetched,
                preservingIDs: inFlight,
                excludingIDs: inFlight.subtracting(posts.lazy.map(\.id))
            )
        if posts != next {
            posts = next
        }
    }

    private func handleLoadError(_ error: Error, userInitiated: Bool) {
        if Task.isCancelled {
            return
        }
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
            do {
                let service = try await self.resolveService()
                let count = try await service.unreadNotificationCount()
                try Task.checkCancellation()
                self.finishUnreadRefresh(id: id, count: count)
            } catch is CancellationError {
                return
            } catch {
                guard self.unreadTaskID == id else { return }
                Log.feed.error("refreshing unread notification count failed: \(error)")
                self.finishUnreadRefresh(id: id, count: nil)
            }
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

    func cancelUnreadRefresh() {
        unreadTask?.cancel()
        unreadTask = nil
        unreadTaskID = nil
        unreadRefreshPending = false
    }
}
