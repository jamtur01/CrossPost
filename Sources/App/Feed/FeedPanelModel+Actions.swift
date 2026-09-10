import Foundation

@MainActor
extension FeedPanelModel {
    func setFollowing(
        _ following: Bool,
        for id: String,
        current: AccountRelationship
    ) async throws -> AccountRelationship {
        let generation = mutationGeneration
        beginFollowMutation(for: id)
        defer { finishFollowMutation(for: id) }
        let updated = try await lifecycleOperation(generation: generation) { service in
            try self.requireOtherAccount(id)
            return try await service.setFollowing(following, for: id, current: current)
        }
        reconcileFollow(updated, for: id)
        return updated
    }

    /// Performs the notification row's one-way follow without publishing shared UI state.
    func remoteFollow(
        actorID: String,
        generation: UInt
    ) async throws -> AccountRelationship {
        beginFollowMutation(for: actorID)
        defer { finishFollowMutation(for: actorID) }
        return try await lifecycleOperation(generation: generation) { service in
            try self.requireOtherAccount(actorID)
            let current = try await service.relationship(with: actorID)
            try self.checkLifecycleGeneration(generation)
            if current.isFollowing {
                return current
            }
            return try await service.setFollowing(true, for: actorID, current: current)
        }
    }

    /// Publishes a relationship only after the initiating UI lifecycle accepts it.
    func reconcileFollow(_ relationship: AccountRelationship, for actorID: String) {
        if relationship.isFollowing {
            followedActorIDs.insert(actorID)
        } else {
            followedActorIDs.remove(actorID)
        }
    }

    /// Whether the signed-in user follows this actor, per the latest batch resolve.
    func isFollowing(_ actorID: String) -> Bool {
        followedActorIDs.contains(actorID)
    }

    /// Resolve follow state for a page of notification actors in one round-trip
    /// (Bluesky pages by 25), so rows show the real state instead of a default.
    /// Merges the result into the shared set rather than replacing it, so a follow
    /// the user just made on an actor outside this page isn't dropped.
    func refreshFollowStates(for fetched: [FeedNotification], service: FeedService) {
        let ids = Set(fetched.filter { !isOwnAccount(id: $0.actorID, handle: $0.actorHandle) }
            .map(\.actorID)).subtracting([""])
        cancelFollowStateLookup()
        guard !ids.isEmpty else { return }
        var generations: [String: UInt] = [:]
        for actorID in ids {
            generations[actorID] = followStateGenerations[actorID, default: 0]
        }
        let id = UUID()
        followStateTaskID = id
        followStateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let relationships = try await service.relationships(with: Array(ids))
                guard !Task.isCancelled, followStateTaskID == id else { return }
                acceptFollowStates(relationships, expected: generations)
                followStateTask = nil
                followStateTaskID = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, followStateTaskID == id else { return }
                followStateTask = nil
                followStateTaskID = nil
                reportError("Couldn't load follow states. \(error.userMessage)")
                Log.feed.error("loading notification follow states failed: \(error)")
            }
        }
    }

    private func acceptFollowStates(_ relationships: [String: AccountRelationship], expected: [String: UInt]) {
        for (actorID, relationship) in relationships {
            guard let generation = expected[actorID],
                  followStateGenerations[actorID, default: 0] == generation else { continue }
            reconcileFollow(relationship, for: actorID)
        }
    }

    private func beginFollowMutation(for actorID: String) {
        followStateGenerations[actorID, default: 0] &+= 1
    }

    private func finishFollowMutation(for actorID: String) {
        followStateGenerations[actorID, default: 0] &+= 1
    }

    func cancelFollowStateLookup() {
        followStateTaskID = nil
        followStateTask?.cancel()
        followStateTask = nil
    }

    func setMuted(
        _ muted: Bool,
        for id: String,
        current: AccountRelationship
    ) async throws -> AccountRelationship {
        let generation = mutationGeneration
        return try await lifecycleOperation(generation: generation) { service in
            try self.requireOtherAccount(id)
            return try await service.setMuted(muted, for: id, current: current)
        }
    }

    func setBlocked(
        _ blocked: Bool,
        for id: String,
        current: AccountRelationship
    ) async throws -> AccountRelationship {
        let generation = mutationGeneration
        return try await lifecycleOperation(generation: generation) { service in
            try self.requireOtherAccount(id)
            return try await service.setBlocked(blocked, for: id, current: current)
        }
    }

    func followers(of id: String) async throws -> [Profile] {
        try await resolveService().followers(of: id)
    }

    func following(of id: String) async throws -> [Profile] {
        try await resolveService().following(of: id)
    }

    /// Whether a post was authored by the signed-in user (controls delete/pin actions).
    func isMine(_ post: FeedPost) -> Bool {
        isOwnAccount(id: post.authorID, handle: post.authorHandle)
    }

    func isOwnAccount(id: String = "", handle: String = "") -> Bool {
        store.isOwnAccount(target, id: id, handle: handle)
    }

    func requireOtherAccount(_ id: String) throws {
        guard !isOwnAccount(id: id) else {
            throw PosterFactory.ConfigError.message("This action isn't available for your own account.")
        }
    }

    func messages(
        in conversationID: String,
        generation: UInt
    ) async throws -> [DirectMessage] {
        try await lifecycleOperation(generation: generation) { service in
            try await service.messages(in: conversationID)
        }
    }

    func sendMessage(
        _ text: String,
        to conversationID: String,
        generation: UInt
    ) async throws {
        try await lifecycleOperation(generation: generation) { service in
            try await service.sendMessage(text, to: conversationID)
        }
    }

    /// Refresh the conversation list (last-message previews, ordering) after activity.
    func reloadConversations(generation: UInt) async throws {
        let fetched = try await lifecycleOperation(generation: generation) { service in
            try await service.conversations()
        }
        if conversations != fetched {
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
        if let index = posts.firstIndex(where: { $0.id == id }) {
            mutate(&posts[index])
        }
    }

    // MARK: OptimisticPostHost — the remote calls the shared engine drives.

    // Also the service bridge PostList uses for its own rows.

    func remoteSetLiked(
        _ liked: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await lifecycleOperation(generation: generation) { service in
            try await service.setLiked(liked, on: post)
        }
    }

    func remoteSetReposted(
        _ reposted: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await lifecycleOperation(generation: generation) { service in
            try await service.setReposted(reposted, on: post)
        }
    }

    func remoteSetBookmarked(
        _ bookmarked: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await lifecycleOperation(generation: generation) { service in
            try await service.setBookmarked(bookmarked, on: post)
        }
    }

    func remoteSetPinned(
        _ pinned: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await lifecycleOperation(generation: generation) { service in
            try await service.setPinned(pinned, on: post)
        }
    }

    func remoteDelete(_ post: FeedPost, generation: UInt) async throws {
        try await lifecycleOperation(generation: generation) { service in
            try await service.deletePost(post)
        }
    }

    private func lifecycleOperation<Value>(
        generation: UInt,
        operation: (FeedService) async throws -> Value
    ) async throws -> Value {
        try checkLifecycleGeneration(generation)
        let service = try await resolveService()
        try checkLifecycleGeneration(generation)
        let value = try await operation(service)
        try checkLifecycleGeneration(generation)
        return value
    }

    private func checkLifecycleGeneration(_ generation: UInt) throws {
        try Task.checkCancellation()
        guard mutationGeneration == generation else { throw CancellationError() }
    }
}
