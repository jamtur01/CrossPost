import Foundation
import TootSDK

extension PagedResult {
    /// Adapt TootSDK's `PagedResult` to the shared `paged(…)` helper's tuple form:
    /// the page's items plus the cursor for the next (older) page.
    var page: (items: T, cursor: PagedInfo?) {
        (result, previousPage)
    }
}

struct MastodonFeedService: FeedService {
    private let client: TootClient
    private let quoteSupport = QuoteSupportCache()
    private let streamOwner = MastodonStreamOwner()

    init(client: TootClient) {
        self.client = client
    }

    func loadFeed(_ kind: FeedKind, includeHistory: Bool,
                  onPage: @Sendable ([FeedPost]) async -> Void) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let posts = try await paged(target: 80, maxPages: includeHistory ? 2 : 1, onPage: { posts in
                await onPage(posts.map { Self.feedPost(from: $0) })
            }, {
                try await client.getTimeline(.home, pageInfo: $0, limit: 40).page
            })
            return posts.map { Self.feedPost(from: $0) }
        case .notifications, .messages:
            return [] // these load through their own methods, not as posts
        }
    }

    func notifications(includeHistory: Bool,
                       onPage: @Sendable ([FeedNotification]) async -> Void) async throws -> [FeedNotification] {
        // 30 is Mastodon's documented per-page max for notifications.
        let notes = try await paged(target: 80, maxPages: includeHistory ? 3 : 1, onPage: { notes in
            await onPage(notes.map { Self.notification(from: $0) })
        }, {
            try await client.getNotifications(params: .init(), $0, limit: 30).page
        })
        return notes.map { Self.notification(from: $0) }
    }

    func unreadNotificationCount() async throws -> Int {
        try await client.getNotificationsUnreadCount()
    }

    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        guard let latest else { return }
        _ = try await client.updateMarkers(notificationsLastReadId: latest.id)
    }

    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = liked
            ? try await client.favouritePost(id: id)
            : try await client.unfavouritePost(id: id)
        var copy = post
        copy.isLiked = updated.favourited ?? liked
        return copy
    }

    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = reposted
            ? try await client.boostPost(id: id)
            : try await client.unboostPost(id: id)
        var copy = post
        copy.isReposted = updated.reposted ?? reposted
        return copy
    }

    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility: PostVisibility) async throws -> PostedItem {
        guard case let .mastodon(id) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        try TargetLimits().checkImageCount(images.count, for: .mastodon)
        let maxBytes = images.isEmpty ? 0 : await client.mastodonImageByteLimit()
        let mediaIds = try await client.uploadJPEGImages(images, maxBytes: maxBytes)
        // Carry the parent's content warning forward; the caller seeds visibility
        // from the parent so a reply never widens its audience.
        let spoiler = (post.spoilerText?.isEmpty == false) ? post.spoilerText : nil
        var params = PostParams(post: text, visibility: visibility.tootVisibility, spoilerText: spoiler)
        if !mediaIds.isEmpty {
            params.mediaIds = mediaIds
        }
        params.inReplyToId = id
        params.sensitive = post.isSensitive
        let posted = try await client.publishPost(params)
        return PostedItem(url: posted.url, ref: .mastodon(statusID: posted.id))
    }

    func quote(post: FeedPost, text: String, visibility: PostVisibility) async throws -> PostedItem {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        // Pre-4.4 servers silently ignore `quotedId` and publish a plain status —
        // the user believes they quoted. Refuse up front instead.
        try await ensureQuoteSupport()
        var params = PostParams(post: text, visibility: visibility.tootVisibility)
        params.quotedId = id
        let posted = try await client.publishPost(params)
        return PostedItem(url: posted.url, ref: .mastodon(statusID: posted.id))
    }

    /// Throw unless the instance advertises quote-post support (Mastodon 4.4+).
    /// The verdict is cached per service instance — server version can't change
    /// mid-session. An unparseable version (forks) proceeds best-effort.
    private func ensureQuoteSupport() async throws {
        let supported: Bool
        if let cached = await quoteSupport.get() {
            supported = cached
        } else {
            let version = try await client.getInstanceInfo().version
            supported = Self.supportsQuotePosts(version: version) ?? true
            await quoteSupport.set(supported)
        }
        guard supported else {
            throw FeedError.notSupported("Quote posts require Mastodon 4.4 or later.")
        }
    }

    func thread(of post: FeedPost) async throws -> PostThread {
        guard case let .mastodon(id) = post.nativeRef else {
            return PostThread(ancestors: [], descendants: [])
        }
        let context = try await client.getContext(id: id)
        return PostThread(
            ancestors: context.ancestors.map { Self.feedPost(from: $0) },
            descendants: context.descendants.map { Self.feedPost(from: $0) }
        )
    }

    func profile(id: String) async throws -> Profile {
        try await Self.profile(from: client.getAccount(by: id))
    }

    func myProfile() async throws -> Profile {
        try await Self.profile(from: client.verifyCredentials())
    }

    func authorPosts(id: String) async throws -> [FeedPost] {
        try await paged(target: 80, maxPages: 2) {
            try await client.getTimeline(.user(userID: id), pageInfo: $0, limit: 40).page
        }.map { Self.feedPost(from: $0) }
    }

    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        guard case let .mastodon(statusID) = post.nativeRef else { throw FeedError.wrongPlatform }
        try await client.report(ReportParams(
            accountId: post.authorID, category: reason.mastodonCategory,
            postIds: [statusID], comment: comment.nilIfBlank
        ))
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        try await client.report(ReportParams(
            accountId: id, category: reason.mastodonCategory,
            comment: comment.nilIfBlank
        ))
    }

    func pinnedPosts(of id: String) async throws -> [FeedPost] {
        let query = UserTimelineQuery(userId: id, pinned: true)
        let posts = try await client.getTimeline(.user(query), limit: 40).result
        return posts.map { Self.feedPost(from: $0) }
    }

    func search(_ query: String) async throws -> SearchResults {
        // resolve: true so a full "@user@instance" handle resolves a remote account.
        let result = try await client.search(params: SearchParams(query: query, resolve: true), limit: 20)
        return SearchResults(
            accounts: result.accounts.map(Self.profile(from:)),
            posts: result.posts.map(Self.feedPost(from:))
        )
    }

    func bookmarkedPosts() async throws -> [FeedPost] {
        try await paged(target: 80, maxPages: 2) {
            try await client.getTimeline(.bookmarks, pageInfo: $0, limit: 40).page
        }.map { Self.feedPost(from: $0) }
    }

    func likedPosts() async throws -> [FeedPost] {
        try await paged(target: 80, maxPages: 2) {
            try await client.getTimeline(.favourites, pageInfo: $0, limit: 40).page
        }.map { Self.feedPost(from: $0) }
    }

    func deletePost(_ post: FeedPost) async throws {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        _ = try await client.deletePost(id: id)
    }

    func editableSource(of post: FeedPost) async throws -> EditableSource {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let source = try await client.getPostSource(id: id)
        return EditableSource(text: source.text, spoiler: source.spoilerText)
    }

    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        // Re-attach the post's existing media (and keep its sensitivity) so an
        // edit to the text alone never drops the images.
        let current = try await client.getPost(id: id)
        var params = EditPostParams(post: text)
        params.spoilerText = spoiler.nilIfBlank
        // `current` was just fetched, so its sensitive flag is authoritative;
        // the caller's post may be stale.
        params.sensitive = current.sensitive
        let mediaIds = current.mediaAttachments.map(\.id)
        if !mediaIds.isEmpty {
            params.mediaIds = mediaIds
        }
        let updated = try await client.editPost(id: id, params)
        return Self.feedPost(from: updated)
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = bookmarked
            ? try await client.bookmarkPost(id: id)
            : try await client.unbookmarkPost(id: id)
        var copy = post
        copy.isBookmarked = updated.bookmarked ?? bookmarked
        return copy
    }

    func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .mastodon(id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = pinned ? try await client.pinPost(id: id) : try await client.unpinPost(id: id)
        var copy = post
        copy.isPinned = updated.pinned ?? pinned
        return copy
    }

    func likedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case let .mastodon(id) = post.nativeRef else { return [] }
        return try await paged(target: 200, maxPages: 3) {
            try await client.getAccountsFavourited(id: id, $0, limit: 80).page
        }.map { Self.profile(from: $0) }
    }

    func repostedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case let .mastodon(id) = post.nativeRef else { return [] }
        return try await paged(target: 200, maxPages: 3) {
            try await client.getAccountsBoosted(id: id, $0, limit: 80).page
        }.map { Self.profile(from: $0) }
    }

    func conversations(includeHistory _: Bool,
                       onPage _: @Sendable ([Conversation]) async -> Void) async throws -> [Conversation] {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }

    func messages(in _: String) async throws -> [DirectMessage] {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }

    func sendMessage(_: String, to _: String) async throws {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }

    func liveUpdates() async -> AsyncStream<FeedUpdate>? {
        do {
            let (id, stream) = try await streamOwner.subscribe(client.streaming)
            let connected = await client.streaming.isConnectionUp
            return AsyncStream { continuation in
                if connected {
                    continuation.yield(.connected)
                }
                let task = Task {
                    do {
                        for try await event in stream {
                            if let update = Self.feedUpdate(from: event) {
                                continuation.yield(update)
                            }
                        }
                    } catch is CancellationError {
                        // Subscription cancellation is normal when a panel stops.
                    } catch {
                        Log.feed.error("Mastodon stream failed: \(error)")
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    task.cancel()
                    Task { await streamOwner.release(id, streaming: client.streaming) }
                }
            }
        } catch {
            Log.feed.error("Mastodon stream subscription failed: \(error)")
            return nil
        }
    }

    static func feedUpdate(from event: StreamingClient.Event) -> FeedUpdate? {
        switch event {
        case .connectionUp: .connected
        case .connectionDown: .disconnected
        case let .receivedEvent(content):
            contentUpdate(from: content)
        }
    }

    private static func contentUpdate(from content: EventContent) -> FeedUpdate? {
        switch content {
        case .update: .home
        case .notification: .notifications
        case .delete, .postUpdate, .filtersChanged: .postChanged
        case .conversation, .announcement, .announcementReaction, .announcementDelete,
             .encryptedMessage, .unsupportedEvent: nil
        }
    }

    func relationship(with id: String) async throws -> AccountRelationship {
        try await Self.relationship(from: client.getRelationships(by: [id]).first)
    }

    func relationships(with ids: [String]) async throws -> [String: AccountRelationship] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: AccountRelationship] = [:]
        for relationship in try await client.getRelationships(by: ids) {
            guard let id = relationship.id else { continue }
            result[id] = Self.relationship(from: relationship)
        }
        return result
    }

    func setFollowing(_ following: Bool, for id: String,
                      current _: AccountRelationship) async throws -> AccountRelationship {
        try await Self.relationship(from: following
            ? client.followAccount(by: id)
            : client.unfollowAccount(by: id))
    }

    func setMuted(_ muted: Bool, for id: String,
                  current _: AccountRelationship) async throws -> AccountRelationship {
        try await Self.relationship(from: muted
            ? client.muteAccount(by: id)
            : client.unmuteAccount(by: id))
    }

    func setBlocked(_ blocked: Bool, for id: String,
                    current _: AccountRelationship) async throws -> AccountRelationship {
        try await Self.relationship(from: blocked
            ? client.blockAccount(by: id)
            : client.unblockAccount(by: id))
    }

    func followers(of id: String) async throws -> [Profile] {
        try await paged(target: 200, maxPages: 3) {
            try await client.getFollowers(for: id, $0, limit: 80).page
        }.map { Self.profile(from: $0) }
    }

    func following(of id: String) async throws -> [Profile] {
        try await paged(target: 200, maxPages: 3) {
            try await client.getFollowing(for: id, $0, limit: 80).page
        }.map { Self.profile(from: $0) }
    }

    func profile(forURL url: URL) async throws -> Profile? {
        guard ProfileLink.isMastodonProfileURL(url) else { return nil }
        // Search with WebFinger resolution turns a profile URL — including a remote
        // account the instance hasn't cached — into a local account record.
        let params = SearchAccountsParams(query: url.absoluteString, resolve: true)
        guard let account = try await client.searchAccounts(params: params, limit: 1).first else {
            return nil
        }
        return Self.profile(from: account)
    }
}

/// A canceled subscription must not disconnect a newer subscription on the same client.
private actor MastodonStreamOwner {
    private var owner: UUID?

    func subscribe(_ streaming: StreamingClient) async throws -> (UUID, StreamingClient.Stream) {
        let id = UUID()
        owner = id
        do {
            return try await (id, streaming.subscribe(to: .user))
        } catch {
            await release(id, streaming: streaming)
            throw error
        }
    }

    func release(_ id: UUID, streaming: StreamingClient) async {
        guard owner == id else { return }
        owner = nil
        await streaming.disconnect()
    }
}

enum FeedError: Error, CustomStringConvertible, LocalizedError {
    case wrongPlatform
    case notSupported(String)

    var description: String {
        switch self {
        case .wrongPlatform: "This action does not apply to this post's platform"
        case let .notSupported(what): what
        }
    }

    var errorDescription: String? {
        description
    }
}

/// Session-scoped cache of the instance's quote-post capability. A reference
/// type so copies of the (struct) service share one verdict, mirroring
/// BlueskyFeedService's OwnDIDCache.
private actor QuoteSupportCache {
    private var supported: Bool?
    func get() -> Bool? {
        supported
    }

    func set(_ value: Bool) {
        supported = value
    }
}
