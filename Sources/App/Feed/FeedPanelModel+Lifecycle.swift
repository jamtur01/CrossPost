import AppKit
import Foundation

@MainActor
extension FeedPanelModel {
    /// Subscribe to Mastodon's live stream. Each event requests a refresh; the load
    /// coordinator permits one active request and one trailing request for a burst.
    func startLiveUpdates() {
        isLiveConnected = false
        liveTaskID = nil
        liveTask?.cancel()
        liveTask = nil
        guard target == .mastodon else { return }
        let id = UUID()
        liveTaskID = id
        liveTask = Task { [weak self] in
            defer { self?.liveTaskDidExit() }
            var backoff: UInt64 = 2_000_000_000
            while !Task.isCancelled {
                let stream = await self?.liveStream()
                if let stream {
                    guard self?.setLiveConnected(true, ownedBy: id) == true else { return }
                    backoff = 2_000_000_000
                    for await _ in stream {
                        if Task.isCancelled {
                            break
                        }
                        guard let self else { break }
                        if self.applicationIsActive() {
                            self.enqueueLoad(reset: false, userInitiated: false)
                            self.refreshUnreadCount()
                        }
                    }
                    guard self?.setLiveConnected(false, ownedBy: id) == true else { return }
                }
                if Task.isCancelled || self == nil {
                    break
                }
                let delay = "\(backoff / 1_000_000_000)s"
                Log.feed.debug(
                    "mastodon live stream dropped; reconnecting in \(delay, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: backoff)
                backoff = min(backoff * 2, 60_000_000_000)
            }
        }
    }

    private func liveStream() async -> AsyncStream<Void>? {
        guard let service = try? await resolveService() else { return nil }
        return await service.liveUpdates()
    }

    private func setLiveConnected(_ connected: Bool, ownedBy id: UUID) -> Bool {
        guard liveTaskID == id else { return false }
        isLiveConnected = connected
        return true
    }

    func resolveService() async throws -> FeedService {
        while true {
            try Task.checkCancellation()
            if let service {
                return service
            }

            let resolution: ServiceResolution
            if let serviceResolution {
                resolution = serviceResolution
            } else {
                let id = UUID()
                let task = Task {
                    let resolved = try await makeService(target, store)
                    try Task.checkCancellation()
                    return resolved
                }
                resolution = ServiceResolution(id: id, task: task)
                serviceResolution = resolution
            }

            let resolved: FeedService
            do {
                resolved = try await resolution.task.value
            } catch {
                if serviceResolution?.id == resolution.id {
                    serviceResolution = nil
                }
                try Task.checkCancellation()
                if resolution.task.isCancelled && serviceResolutionIsActive {
                    continue
                }
                throw error
            }

            try Task.checkCancellation()
            if resolution.task.isCancelled {
                if serviceResolution?.id == resolution.id {
                    serviceResolution = nil
                }
                if serviceResolutionIsActive {
                    continue
                }
                throw CancellationError()
            }
            guard serviceResolution?.id == resolution.id else { continue }
            serviceResolution = nil
            service = resolved
            return resolved
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
            do {
                let ref = try await self.profileRef(forURL: url)
                guard !Task.isCancelled,
                      self.profileLinkGeneration == generation else { return }
                self.profileLinkTask = nil
                if let ref {
                    push(.profile(ref))
                } else {
                    self.open(url)
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.profileLinkGeneration == generation else { return }
                self.profileLinkTask = nil
                self.reportError("Couldn't open profile. \(error.userMessage)")
                Log.feed.error("resolving profile link \(url) failed: \(error)")
            }
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

    private func profileRef(forURL url: URL) async throws -> ProfileRef? {
        try await resolveService().profile(forURL: url)?.profileRef()
    }
}
