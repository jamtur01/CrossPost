import SwiftUI

/// The one optimistic-mutation engine shared by every post collection — the feed
/// timeline (`FeedPanelModel`) and the route lists (`PostList`). A conformer owns
/// its rows, in-flight ids, task handles, and lifecycle generation. The engine
/// updates the UI immediately, calls the remote action, then reconciles on success
/// or reverts on failure while the initiating host generation remains current.
///
/// Conformers supply the ownership storage, remote calls (`remoteSet*`/
/// `remoteDelete`), and an error sink; mutation behavior lives here once.
@MainActor
protocol OptimisticPostHost: AnyObject {
    var posts: [FeedPost] { get set }
    /// Ids with an in-flight mutation — also read by the timeline's load/merge so a
    /// background poll can't clobber a row mid-flight.
    var inFlight: Set<String> { get set }
    var mutationTasks: [String: Task<Void, Never>] { get set }
    var mutationGeneration: UInt { get set }
    var remoteMutationGeneration: UInt { get }

    func reportError(_ message: String)

    func remoteSetLiked(
        _ liked: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost
    func remoteSetReposted(
        _ reposted: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost
    func remoteSetBookmarked(
        _ bookmarked: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost
    func remoteSetPinned(
        _ pinned: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost
    func remoteDelete(_ post: FeedPost, generation: UInt) async throws
}

extension OptimisticPostHost {
    var remoteMutationGeneration: UInt {
        mutationGeneration
    }

    func toggleLike(_ post: FeedPost) {
        Haptics.tap()
        mutate(
            post,
            optimistic: {
                $0.isLiked.toggle()
                $0.likeCount = max(0, $0.likeCount + ($0.isLiked ? 1 : -1))
            },
            action: {
                try await self.remoteSetLiked($0.isLiked, on: $0, generation: $1)
            }
        )
    }

    func toggleRepost(_ post: FeedPost) {
        Haptics.tap()
        mutate(
            post,
            optimistic: {
                $0.isReposted.toggle()
                $0.repostCount = max(0, $0.repostCount + ($0.isReposted ? 1 : -1))
            },
            action: {
                try await self.remoteSetReposted($0.isReposted, on: $0, generation: $1)
            }
        )
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) {
        mutate(
            post,
            optimistic: { $0.isBookmarked = bookmarked },
            action: {
                try await self.remoteSetBookmarked(bookmarked, on: $0, generation: $1)
            }
        )
    }

    func setPinned(_ pinned: Bool, on post: FeedPost) {
        mutate(
            post,
            optimistic: { $0.isPinned = pinned },
            action: {
                try await self.remoteSetPinned(pinned, on: $0, generation: $1)
            }
        )
    }

    /// Optimistically remove a row, deleting it on the server and re-inserting it
    /// next to its old neighbors (with an error banner) if the delete fails.
    func delete(_ post: FeedPost) {
        guard !inFlight.contains(post.id),
              let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        inFlight.insert(post.id)
        let generation = mutationGeneration
        let remoteGeneration = remoteMutationGeneration
        let previousID = index > 0 ? posts[index - 1].id : nil
        let removed = posts.remove(at: index)
        let nextID = index < posts.count ? posts[index].id : nil
        mutationTasks[post.id] = Task {
            do {
                try await remoteDelete(post, generation: remoteGeneration)
            } catch is CancellationError {
                guard mutationGeneration == generation else { return }
                restoreDeletedPost(
                    removed,
                    at: index,
                    previousID: previousID,
                    nextID: nextID
                )
            } catch {
                guard mutationGeneration == generation else { return }
                restoreDeletedPost(
                    removed,
                    at: index,
                    previousID: previousID,
                    nextID: nextID
                )
                reportError(error.userMessage)
            }
            finishMutation(post.id, generation: generation)
        }
    }

    /// Replace a row in place after an edit (same id, new content), so a surface
    /// shows the edit without a full reload.
    func replace(_ post: FeedPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
    }

    /// Flip the UI immediately, call the remote action, reconcile or revert on
    /// failure. Ignores a second mutation of the same post while one is in flight;
    /// reconciles only if a concurrent refresh hasn't already replaced the row.
    func mutate(
        _ post: FeedPost,
        optimistic: (inout FeedPost) -> Void,
        action: @escaping (FeedPost, UInt) async throws -> FeedPost
    ) {
        guard !inFlight.contains(post.id),
              let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        inFlight.insert(post.id)
        let generation = mutationGeneration
        let remoteGeneration = remoteMutationGeneration
        let original = posts[index]
        var optimisticPost = original
        optimistic(&optimisticPost)
        posts[index] = optimisticPost
        mutationTasks[post.id] = Task {
            do {
                let updated = try await action(optimisticPost, remoteGeneration)
                guard mutationGeneration == generation else { return }
                if let index = posts.firstIndex(where: { $0.id == post.id }),
                   posts[index] == optimisticPost {
                    posts[index] = updated
                }
            } catch is CancellationError {
                guard mutationGeneration == generation else { return }
                restoreMutation(original, ifCurrent: optimisticPost)
            } catch {
                guard mutationGeneration == generation else { return }
                restoreMutation(original, ifCurrent: optimisticPost)
                reportError(error.userMessage)
            }
            finishMutation(post.id, generation: generation)
        }
    }

    /// End this host lifecycle without allowing cancellation-insensitive remote work
    /// to publish into the next lifecycle.
    func invalidateOptimisticMutations() {
        mutationGeneration += 1
        mutationTasks.values.forEach { $0.cancel() }
        mutationTasks.removeAll()
        inFlight.removeAll()
    }

    private func restoreMutation(_ original: FeedPost, ifCurrent optimisticPost: FeedPost) {
        if let index = posts.firstIndex(where: { $0.id == optimisticPost.id }),
           posts[index] == optimisticPost {
            posts[index] = original
        }
    }

    private func finishMutation(_ postID: String, generation: UInt) {
        guard mutationGeneration == generation else { return }
        inFlight.remove(postID)
        mutationTasks[postID] = nil
    }

    private func restoreDeletedPost(
        _ post: FeedPost,
        at index: Int,
        previousID: String?,
        nextID: String?
    ) {
        guard !posts.contains(where: { $0.id == post.id }) else { return }
        if let previousID,
           let previousIndex = posts.firstIndex(where: { $0.id == previousID }) {
            posts.insert(post, at: previousIndex + 1)
        } else if let nextID,
                  let nextIndex = posts.firstIndex(where: { $0.id == nextID }) {
            posts.insert(post, at: nextIndex)
        } else {
            posts.insert(post, at: min(index, posts.count))
        }
    }
}
