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
    var errorMessage: String?
    var needsCredentials = false

    private let store: AccountStore
    private var service: FeedService?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: UInt64 = 60_000_000_000 // 60s in nanoseconds

    init(target: PostTarget, store: AccountStore) {
        self.target = target
        self.store = store
    }

    private var hasCredentials: Bool {
        target == .mastodon ? store.hasMastodon : store.hasBluesky
    }

    func start() {
        guard hasCredentials else { needsCredentials = true; return }
        Task { await load(reset: true) }
        startPolling()
    }

    func switchTo(_ newKind: FeedKind) {
        guard newKind != kind else { return }
        kind = newKind
        posts = []
        Task { await load(reset: true) }
    }

    func refresh() {
        guard hasCredentials else { needsCredentials = true; return }
        if pollTask == nil { startPolling() }   // start polling if credentials arrived after launch
        Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        guard hasCredentials else { needsCredentials = true; return }
        needsCredentials = false   // credentials present now — clear the connect prompt
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let svc = try await resolveService()
            let fetched = try await svc.loadFeed(kind)
            posts = reset ? fetched : FeedMerge.merge(existing: posts, fetched: fetched)
        } catch {
            errorMessage = String(describing: error)
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

    /// Flip the UI immediately (optimistic), call the service with the new desired
    /// state, then reconcile with the returned post — or revert to the original on failure.
    private func mutate(_ post: FeedPost,
                        optimistic: (inout FeedPost) -> Void,
                        action: @escaping (FeedService, FeedPost) async throws -> FeedPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let original = posts[index]
        var optimisticPost = original
        optimistic(&optimisticPost)
        posts[index] = optimisticPost
        Task {
            do {
                let svc = try await resolveService()
                let updated = try await action(svc, optimisticPost)
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = updated }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = original }
                errorMessage = String(describing: error)
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 60_000_000_000)
                if Task.isCancelled { break }
                await self?.load(reset: false)
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }
}
