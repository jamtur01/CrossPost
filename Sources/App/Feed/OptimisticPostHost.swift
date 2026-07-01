import SwiftUI

/// The one optimistic-mutation engine shared by every post collection — the feed
/// timeline (`FeedPanelModel`) and the route lists (`PostList`). A conformer owns a
/// `posts` array and an `inFlight` id set; the engine flips the UI immediately,
/// calls the remote action, then reconciles on success or reverts on failure,
/// ignoring a second mutation of the same post while one is in flight.
///
/// Conformers supply only the remote calls (`remoteSet*`/`remoteDelete`) and an
/// error sink; the like/repost/bookmark/pin/delete/replace behavior lives here once.
@MainActor
protocol OptimisticPostHost: AnyObject {
    var posts: [FeedPost] { get set }
    /// Ids with an in-flight mutation — also read by the timeline's load/merge so a
    /// background poll can't clobber a row mid-flight.
    var inFlight: Set<String> { get set }

    func reportError(_ message: String)

    func remoteSetLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost
    func remoteSetReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost
    func remoteSetBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost
    func remoteSetPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost
    func remoteDelete(_ post: FeedPost) async throws
}

extension OptimisticPostHost {
    func toggleLike(_ post: FeedPost) {
        Haptics.tap()
        mutate(post, optimistic: {
            $0.isLiked.toggle()
            $0.likeCount = max(0, $0.likeCount + ($0.isLiked ? 1 : -1))
        }) { try await self.remoteSetLiked($0.isLiked, on: $0) }
    }

    func toggleRepost(_ post: FeedPost) {
        Haptics.tap()
        mutate(post, optimistic: {
            $0.isReposted.toggle()
            $0.repostCount = max(0, $0.repostCount + ($0.isReposted ? 1 : -1))
        }) { try await self.remoteSetReposted($0.isReposted, on: $0) }
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) {
        mutate(post, optimistic: { $0.isBookmarked = bookmarked }) {
            try await self.remoteSetBookmarked(bookmarked, on: $0)
        }
    }

    func setPinned(_ pinned: Bool, on post: FeedPost) {
        mutate(post, optimistic: { $0.isPinned = pinned }) {
            try await self.remoteSetPinned(pinned, on: $0)
        }
    }

    /// Optimistically remove a row, deleting it on the server and re-inserting it at
    /// its original position (with an error banner) if the delete fails.
    func delete(_ post: FeedPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let removed = posts.remove(at: index)
        Task {
            do { try await remoteDelete(post) }
            catch {
                if !posts.contains(where: { $0.id == post.id }) {
                    posts.insert(removed, at: min(index, posts.count))
                }
                reportError(error.userMessage)
            }
        }
    }

    /// Replace a row in place after an edit (same id, new content), so a surface
    /// shows the edit without a full reload.
    func replace(_ post: FeedPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = post }
    }

    /// Flip the UI immediately, call the remote action, reconcile or revert on
    /// failure. Ignores a second mutation of the same post while one is in flight;
    /// reconciles only if a concurrent refresh hasn't already replaced the row.
    func mutate(_ post: FeedPost,
                optimistic: (inout FeedPost) -> Void,
                action: @escaping (FeedPost) async throws -> FeedPost) {
        guard !inFlight.contains(post.id),
              let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        inFlight.insert(post.id)
        let original = posts[index]
        var optimisticPost = original
        optimistic(&optimisticPost)
        posts[index] = optimisticPost
        Task {
            defer { inFlight.remove(post.id) }
            do {
                let updated = try await action(optimisticPost)
                if let i = posts.firstIndex(where: { $0.id == post.id }), posts[i] == optimisticPost {
                    posts[i] = updated
                }
            } catch {
                // Always revert by id, even if a concurrent refresh touched the row,
                // so the optimistic state never sticks.
                if let i = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[i] = original
                }
                reportError(error.userMessage)
            }
        }
    }
}
