import ATProtoKit
import Foundation

struct BlueskyFeedService: FeedService {
    private let kit: ATProtoKit
    private let bluesky: ATProtoBluesky
    private let chat: ATProtoBlueskyChat
    private let handle: String
    private let didCache = OwnDIDCache()
    private let notificationPostCache = NotificationPostCache()

    init(kit: ATProtoKit, bluesky: ATProtoBluesky, handle: String) {
        self.kit = kit
        self.bluesky = bluesky
        chat = ATProtoBlueskyChat(atProtoKitInstance: kit)
        self.handle = handle
    }

    /// The signed-in user's DID. Constant for the session, so it's fetched once and
    /// cached — the chat endpoints would otherwise pay a getProfile call each time.
    /// The cache actor owns the in-flight fetch, so concurrent first callers share
    /// one getProfile round-trip instead of racing check-then-act.
    private func ownDID() async throws -> String {
        let kit = kit
        let handle = handle
        return try await didCache.did { try await kit.getProfile(for: handle).actorDID }
    }

    func loadFeed(_ kind: FeedKind, includeHistory: Bool,
                  onPage: @Sendable ([FeedPost]) async -> Void) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let feed = try await paged(target: 100, maxPages: includeHistory ? 2 : 1, onPage: { feed in
                await onPage(feed.compactMap { Self.feedPost(from: $0) })
            }, {
                let output = try await kit.getTimeline(limit: 100, cursor: $0)
                return (output.feed, output.cursor)
            })
            return feed.compactMap { Self.feedPost(from: $0) }
        case .notifications, .messages:
            return [] // these load through their own methods, not as posts
        }
    }

    func notifications(includeHistory: Bool,
                       onPage: @Sendable ([FeedNotification]) async -> Void) async throws -> [FeedNotification] {
        let notes = try await paged(target: 100, maxPages: includeHistory ? 2 : 1, onPage: { notes in
            try await publishNotifications(notes, onPage: onPage)
        }, {
            let output = try await kit.listNotifications(limit: 100, cursor: $0)
            return (output.notifications, output.cursor)
        })
        let cached = await notificationPostCache.snapshot(for: Set(notes.compactMap(Self.referencedURI)))
        return notes.map { Self.notification(from: $0, hydrated: cached.posts) }
    }

    private func publishNotifications(
        _ notes: [AppBskyLexicon.Notification.Notification],
        onPage: @Sendable ([FeedNotification]) async -> Void
    ) async throws {
        let cached = await notificationPostCache.snapshot(for: Set(notes.compactMap(Self.referencedURI)))
        try Task.checkCancellation()
        await onPage(notes.map { Self.notification(from: $0, hydrated: cached.posts) })
        guard !cached.missing.isEmpty else { return }
        let hydrated = try await hydratePosts(cached.missing)
        try Task.checkCancellation()
        await notificationPostCache.insert(hydrated, requested: cached.missing, generation: cached.generation)
        let current = await notificationPostCache.snapshot(for: Set(notes.compactMap(Self.referencedURI)))
        guard current.generation == cached.generation else { return }
        await onPage(notes.map { Self.notification(from: $0, hydrated: current.posts) })
    }

    func unreadNotificationCount() async throws -> Int {
        try await kit.getUnreadCount(priority: nil).count
    }

    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        // Mark everything seen as of now, matching the official Bluesky client, which
        // sends its sync time rather than a notification's timestamp. The server only
        // clears a notification when the stored seen time is strictly past it, and it
        // also counts notifications that listNotifications hides (muted, needs-review,
        // etc.) - so echoing the newest *shown* notification's timestamp can leave a
        // hidden or same-millisecond one counted forever. "Now" is strictly past every
        // notification the server has indexed. `latest` gates the call so an empty list
        // doesn't fire a pointless write.
        guard latest != nil else { return }
        try await kit.updateSeen(seenAt: Date())
    }

    /// Hydrate posts by AT-URI. getPosts accepts up to 25 at a time, so the
    /// chunks are fetched concurrently rather than one round-trip after another.
    private func hydratePosts(_ uris: [String]) async throws
        -> [String: FeedPost] {
        let chunks = stride(from: 0, to: uris.count, by: 25).map {
            Array(uris[$0 ..< min($0 + 25, uris.count)])
        }
        var result: [String: FeedPost] = [:]
        try await withThrowingTaskGroup(of: [AppBskyLexicon.Feed.PostViewDefinition].self) { group in
            for chunk in chunks {
                group.addTask { try await kit.getPosts(chunk).posts }
            }
            for try await posts in group {
                for post in posts {
                    result[post.uri] = Self.feedPost(fromPostView: post)
                }
            }
        }
        return result
    }

    /// Build a StrongReference (the uri+cid pair the write APIs take) tersely.
    private static func strongRef(_ uri: String, _ cid: String)
        -> ComAtprotoLexicon.Repository.StrongReference {
        .init(recordURI: uri, cidHash: cid)
    }

    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .bluesky(uri, cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        await notificationPostCache.invalidate(uri)
        var copy = post
        if liked {
            // Already liked with a known record: creating a second like would
            // orphan the first server-side (only the newest URI would be kept
            // for undo), so a repeated like is a no-op.
            if let existing = post.likeRecordURI {
                copy.isLiked = true
                copy.likeRecordURI = existing
                return copy
            }
            let likeRef = try await bluesky.createLikeRecord(Self.strongRef(uri, cid))
            copy.isLiked = true
            copy.likeRecordURI = likeRef.recordURI
        } else if let likeURI = post.likeRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
            copy.isLiked = false
            copy.likeRecordURI = nil
        }
        await notificationPostCache.invalidate(uri)
        return copy
    }

    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .bluesky(uri, cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        await notificationPostCache.invalidate(uri)
        var copy = post
        if reposted {
            // Same idempotency guard as setLiked: never create a duplicate record.
            if let existing = post.repostRecordURI {
                copy.isReposted = true
                copy.repostRecordURI = existing
                return copy
            }
            let repostRef = try await bluesky.createRepostRecord(Self.strongRef(uri, cid))
            copy.isReposted = true
            copy.repostRecordURI = repostRef.recordURI
        } else if let repostURI = post.repostRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
            copy.isReposted = false
            copy.repostRecordURI = nil
        }
        await notificationPostCache.invalidate(uri)
        return copy
    }

    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility _: PostVisibility) async throws -> PostedItem {
        guard case let .bluesky(uri, cid, rootURI, rootCID) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        let parent = Self.strongRef(uri, cid)
        let root = Self.strongRef(rootURI, rootCID)
        let replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(root: root, parent: parent)

        let embed = try BlueskyPoster.imagesEmbed(from: images)
        let ref = try await bluesky.createPostRecord(text: text, replyTo: replyRef, embed: embed)
        // The reply keeps the parent's thread root, so a continuation threads correctly.
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: rootURI, rootCID: rootCID)
        return PostedItem(url: BlueskyURL.post(recordURI: ref.recordURI, handle: handle), ref: nativeRef)
    }

    func quote(post: FeedPost, text: String, visibility _: PostVisibility) async throws -> PostedItem {
        guard case let .bluesky(uri, cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        let ref = try await bluesky.createPostRecord(
            text: text,
            embed: .record(strongReference: .init(recordURI: uri, cidHash: cid))
        )
        // A quote is a fresh top-level post, so it is its own thread root.
        let nativeRef = NativeRef.bluesky(uri: ref.recordURI, cid: ref.recordCID,
                                          rootURI: ref.recordURI, rootCID: ref.recordCID)
        return PostedItem(url: BlueskyURL.post(recordURI: ref.recordURI, handle: handle), ref: nativeRef)
    }

    func thread(of post: FeedPost) async throws -> PostThread {
        guard case let .bluesky(uri, _, _, _) = post.nativeRef else {
            return PostThread(ancestors: [], descendants: [])
        }
        let output = try await kit.getPostThread(from: uri)
        guard case let .threadViewPost(thread) = output.thread else {
            return PostThread(ancestors: [], descendants: [])
        }
        var ancestors: [FeedPost] = []
        var node = thread.parent
        while case let .threadViewPost(parent)? = node {
            ancestors.append(Self.feedPost(fromPostView: parent.post))
            node = parent.parent
        }
        ancestors.reverse()

        // Walk the full reply tree (depth-first, parents before their children).
        var descendants: [FeedPost] = []
        var stack: [AppBskyLexicon.Feed.ThreadViewPostDefinition] = Self.childThreads(of: thread).reversed()
        while let node = stack.popLast() {
            descendants.append(Self.feedPost(fromPostView: node.post))
            stack.append(contentsOf: Self.childThreads(of: node).reversed())
        }
        return PostThread(ancestors: ancestors, descendants: descendants)
    }

    func profile(id: String) async throws -> Profile {
        try await Self.profile(fromDetailed: kit.getProfile(for: id))
    }

    func profile(forURL url: URL) async throws -> Profile? {
        guard let id = ProfileLink.blueskyID(from: url) else { return nil }
        return try await profile(id: id)
    }

    func deletePost(_ post: FeedPost) async throws {
        guard case let .bluesky(uri, _, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        try await bluesky.deleteRecord(.recordURI(atURI: uri))
        await notificationPostCache.invalidate(uri)
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case let .bluesky(uri, cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        if bookmarked {
            try await kit.createBookmark(uri: uri, cid: cid)
        } else {
            try await kit.deleteBookmark(uri: uri)
        }
        await notificationPostCache.invalidate(uri)
        var copy = post
        copy.isBookmarked = bookmarked
        await notificationPostCache.invalidate(uri)
        return copy
    }

    func setPinned(_: Bool, on _: FeedPost) async throws -> FeedPost {
        throw FeedError.notSupported("Pinning posts isn't supported on Bluesky yet.")
    }

    func editableSource(of _: FeedPost) async throws -> EditableSource {
        throw FeedError.notSupported("Bluesky posts can't be edited.")
    }

    func edit(post _: FeedPost, text _: String, spoiler _: String) async throws -> FeedPost {
        throw FeedError.notSupported("Bluesky posts can't be edited.")
    }

    func likedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case let .bluesky(uri, _, _, _) = post.nativeRef else { return [] }
        let likes = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getLikes(from: uri, limit: 100, cursor: $0)
            return (output.likes, output.cursor)
        }
        return likes.map { Self.profile(fromBasic: $0.actor) }
    }

    func repostedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case let .bluesky(uri, _, _, _) = post.nativeRef else { return [] }
        let actors = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getRepostedBy(uri, limit: 100, cursor: $0)
            return (output.repostedBy, output.cursor)
        }
        return actors.map { Self.profile(fromBasic: $0) }
    }

    func conversations(includeHistory: Bool,
                       onPage: @Sendable ([Conversation]) async -> Void) async throws -> [Conversation] {
        let myDID = try await ownDID()
        let convos = try await paged(target: 200, maxPages: includeHistory ? 3 : 1, onPage: { convos in
            await onPage(Self.conversations(from: convos, ownDID: myDID))
        }, {
            let output = try await chat.listConversations(limit: 100, cursor: $0)
            return (output.conversations, output.cursor)
        })
        return Self.conversations(from: convos, ownDID: myDID)
    }

    private static func conversations(
        from convos: [ChatBskyLexicon.Conversation.ConversationViewDefinition], ownDID: String
    ) -> [Conversation] {
        convos.compactMap { convo in
            // Fall back to the first member for a self-conversation (DM to yourself).
            guard let other = convo.members.first(where: { $0.actorDID != ownDID }) ?? convo.members.first
            else { return nil }
            let last = Self.lastMessage(convo.lastMessage)
            return Conversation(
                id: convo.conversationID,
                otherName: displayOrHandle(other.displayName, other.actorHandle),
                otherHandle: "@\(other.actorHandle)", otherID: other.actorDID,
                otherAvatarURL: other.avatarImageURL,
                lastMessage: last.text, lastDate: last.date, unreadCount: convo.unreadCount
            )
        }
    }

    func messages(in conversationID: String) async throws -> [DirectMessage] {
        let myDID = try await ownDID()
        // ATProtoKit's getMessages exposes no cursor, so fetch its max page (100).
        // Deep DM history beyond one page isn't reachable until the SDK adds a cursor.
        let output = try await chat.getMessages(from: conversationID, limit: 100)
        let messages = output.messages.compactMap { message -> DirectMessage? in
            guard case let .messageView(message) = message else { return nil }
            return DirectMessage(id: message.messageID, text: message.text, date: message.sentAt,
                                 isFromMe: message.sender.authorDID == myDID)
        }
        return messages.reversed() // getMessages returns newest-first; show oldest-first
    }

    func sendMessage(_ text: String, to conversationID: String) async throws {
        _ = try await chat.sendMessage(
            to: conversationID,
            message: ChatBskyLexicon.Conversation.MessageInputDefinition(text: text)
        )
    }

    /// Bluesky has no per-user timeline stream (only the global firehose), so it polls.
    func liveUpdates() async -> AsyncStream<FeedUpdate>? {
        nil
    }

    func relationship(with id: String) async throws -> AccountRelationship {
        try await Self.relationship(from: kit.getProfile(for: id).viewer)
    }

    func relationships(with ids: [String]) async throws -> [String: AccountRelationship] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: AccountRelationship] = [:]
        // getProfiles silently caps its input at 25 actors, so page explicitly.
        for chunk in stride(from: 0, to: ids.count, by: 25).map({ Array(ids[$0 ..< min($0 + 25, ids.count)]) }) {
            for profile in try await kit.getProfiles(for: chunk).profiles {
                let relationship = Self.relationship(from: profile.viewer)
                // Callers may hold either form of id; key by whichever they asked with.
                result[profile.actorDID] = relationship
                result[profile.actorHandle] = relationship
            }
        }
        let requested = Set(ids)
        return result.filter { requested.contains($0.key) }
    }

    func setFollowing(_ following: Bool, for id: String,
                      current: AccountRelationship) async throws -> AccountRelationship {
        var rel = current
        if following {
            let ref = try await bluesky.createFollowRecord(actorDID: id)
            rel.isFollowing = true
            rel.followRecordURI = ref.recordURI
        } else if let uri = current.followRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: uri))
            rel.isFollowing = false
            rel.followRecordURI = nil
        }
        return rel
    }

    func setMuted(_ muted: Bool, for id: String,
                  current: AccountRelationship) async throws -> AccountRelationship {
        if muted {
            try await kit.muteActor(id)
        } else {
            try await kit.unmuteActor(id)
        }
        var rel = current
        rel.isMuting = muted
        return rel
    }

    func setBlocked(_ blocked: Bool, for id: String,
                    current: AccountRelationship) async throws -> AccountRelationship {
        var rel = current
        if blocked {
            let ref = try await bluesky.createBlockRecord(ofType: .actorBlock(actorDID: id))
            rel.isBlocking = true
            rel.blockRecordURI = ref.recordURI
        } else if let uri = current.blockRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: uri))
            rel.isBlocking = false
            rel.blockRecordURI = nil
        }
        return rel
    }

    func followers(of id: String) async throws -> [Profile] {
        let actors = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getFollowers(by: id, limit: 100, cursor: $0)
            return (output.followers, output.cursor)
        }
        return actors.map { Self.profile(fromBasic: $0) }
    }

    func following(of id: String) async throws -> [Profile] {
        let actors = try await paged(target: 200, maxPages: 3) {
            let output = try await kit.getFollows(from: id, limit: 100, cursor: $0)
            return (output.follows, output.cursor)
        }
        return actors.map { Self.profile(fromBasic: $0) }
    }

    func myProfile() async throws -> Profile {
        try await Self.profile(fromDetailed: kit.getProfile(for: handle))
    }

    func authorPosts(id: String) async throws -> [FeedPost] {
        let feed = try await paged(target: 100, maxPages: 2) {
            let output = try await kit.getAuthorFeed(by: id, limit: 100, cursor: $0)
            return (output.feed, output.cursor)
        }
        return feed.compactMap { Self.feedPost(from: $0) }
    }

    func pinnedPosts(of _: String) async throws -> [FeedPost] {
        [] // Bluesky pinning isn't supported in this app.
    }

    func search(_ query: String) async throws -> SearchResults {
        // Accounts and posts are independent endpoints, so query them concurrently.
        async let actors = kit.searchActors(matching: query, limit: 20)
        async let posts = kit.searchPosts(matching: query, limit: 20)
        return try await SearchResults(
            accounts: actors.actors.map(Self.profile(fromBasic:)),
            posts: posts.posts.map { Self.feedPost(fromPostView: $0) }
        )
    }

    func bookmarkedPosts() async throws -> [FeedPost] {
        [] // Bluesky has no native bookmarks.
    }

    func likedPosts() async throws -> [FeedPost] {
        let did = try await ownDID()
        let feed = try await paged(target: 100, maxPages: 2) {
            let output = try await kit.getActorLikes(by: did, limit: 100, cursor: $0)
            return (output.feed, output.cursor)
        }
        return feed.compactMap { Self.feedPost(from: $0) }
    }

    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        guard case let .bluesky(uri, cid, _, _) = post.nativeRef else { throw FeedError.wrongPlatform }
        let subject = ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion
            .strongReference(.init(recordURI: uri, cidHash: cid))
        _ = try await kit.createReport(with: reason.blueskyReason,
                                       andContextof: comment.nilIfBlank,
                                       subject: subject)
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        _ = try await kit.createReport(with: reason.blueskyReason,
                                       andContextof: comment.nilIfBlank,
                                       subject: Self.accountReportSubject(did: id))
    }

    /// The report subject for an account. ATProtoKit's repoRef type exposes no
    /// public initializer across the module boundary, so it's built by encoding
    /// the lexicon's own JSON shape (the union keys off `$type`) and decoding it
    /// back — JSONEncoder handles escaping, so a hostile DID can't break the
    /// payload. Static and internal so it can be unit-tested without the network.
    static func accountReportSubject(
        did: String
    ) throws -> ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion {
        let json = try JSONEncoder().encode(RepoRefSubject(did: did))
        return try JSONDecoder().decode(
            ComAtprotoLexicon.Moderation.CreateReportRequestBody.SubjectUnion.self, from: json
        )
    }
}

extension ReportReason {
    /// Closest matching Bluesky moderation reason.
    var blueskyReason: ComAtprotoLexicon.Moderation.ReasonTypeDefinition {
        switch self {
        case .spam: .spam
        case .harassment: .rude
        case .misleading: .misleading
        case .sexual: .sexual
        case .illegal: .violation
        case .other: .other
        }
    }
}

/// Session-scoped cache for the signed-in user's DID. A reference type so copies
/// of the (struct) service share one resolved value. The actor stores the fetch
/// Task itself, so every concurrent first caller awaits the same request and a
/// failure is retried by the next caller rather than cached forever.
private actor OwnDIDCache {
    private var inFlight: Task<String, Error>?

    func did(fetch: @escaping @Sendable () async throws -> String) async throws -> String {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await fetch() }
        inFlight = task
        do {
            return try await task.value
        } catch {
            inFlight = nil
            throw error
        }
    }
}

/// The lexicon wire shape of a `com.atproto.admin.defs#repoRef` subject.
private struct RepoRefSubject: Encodable {
    let did: String

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case did
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("com.atproto.admin.defs#repoRef", forKey: .type)
        try container.encode(did, forKey: .did)
    }
}
