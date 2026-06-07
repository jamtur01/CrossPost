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
    private(set) var scrollToTopToken = 0   // bumped on each user-initiated refresh

    private let store: AccountStore
    private var service: FeedService?
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
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
        guard hasCredentials else { needsCredentials = true; return }
        needsCredentials = false
        enqueueLoad(reset: true)
        startPolling()
    }

    func switchTo(_ newKind: FeedKind) {
        guard newKind != kind else { return }
        kind = newKind
        posts = []
        errorMessage = nil
        enqueueLoad(reset: true)
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
            let fetched = try await svc.loadFeed(kind)
            if Task.isCancelled { return }   // a newer load superseded this one
            errorMessage = nil
            posts = reset
                ? fetched
                : FeedMerge.merge(existing: posts, fetched: fetched, preservingIDs: mutating)
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.userMessage
        }
    }

    private func resolveService() async throws -> FeedService {
        if let service { return service }
        let svc = try await FeedServiceFactory.make(for: target, store: store)
        service = svc
        return svc
    }

    func toggleLike(_ post: FeedPost) {
        mutate(post, optimistic: { $0.isLiked.toggle() }) { svc, p in
            try await svc.setLiked(p.isLiked, on: p)
        }
    }

    func toggleRepost(_ post: FeedPost) {
        mutate(post, optimistic: { $0.isReposted.toggle() }) { svc, p in
            try await svc.setReposted(p.isReposted, on: p)
        }
    }

    func openInBrowser(_ post: FeedPost) {
        guard let url = post.webURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openProfile(_ post: FeedPost) {
        guard let url = post.authorURL else { return }
        NSWorkspace.shared.open(url)
    }

    func open(_ url: URL) {
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
                if NSApplication.shared.isActive { self?.enqueueLoad(reset: false) }
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        loadTask?.cancel(); loadTask = nil
        isLoading = false
    }
}
