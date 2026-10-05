import Foundation

@MainActor
extension FeedPanelModel {
    func receiveLiveUpdate(_ update: FeedUpdate, ownedBy id: UUID) -> Bool {
        guard liveTaskID == id else { return false }
        switch update {
        case .connected: isLiveConnected = true
        case .disconnected: isLiveConnected = false
        case .home: pendingLiveKinds.insert(.home)
        case .notifications:
            pendingLiveKinds.insert(.notifications)
            pendingLiveUnread = true
        case .postChanged:
            pendingLiveKinds.formUnion([.home, .notifications])
        }
        guard update.isContentChange, applicationIsActive() else { return true }
        scheduleLiveRefresh()
        return true
    }

    private func scheduleLiveRefresh() {
        guard liveRefreshTask == nil else { return }
        let delay = liveRefreshDelay
        liveRefreshTask = Task { [weak self] in
            do {
                try await delay()
                try Task.checkCancellation()
            } catch { return }
            self?.flushLiveRefresh()
        }
    }

    private func flushLiveRefresh() {
        liveRefreshTask = nil
        let kinds = pendingLiveKinds
        let unread = pendingLiveUnread
        pendingLiveKinds = []
        pendingLiveUnread = false
        guard applicationIsActive() else { return }
        if kinds.contains(kind) {
            enqueueLoad(userInitiated: false)
        }
        if unread {
            refreshUnreadCount()
        }
    }

    func cancelLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        pendingLiveKinds = []
        pendingLiveUnread = false
    }
}
