import Foundation
import TootSDK

extension PagedResult {
    /// Adapt TootSDK's `PagedResult` to the shared `paged(…)` helper's tuple form:
    /// the page's items plus the cursor for the next (older) page.
    var page: (items: T, cursor: PagedInfo?) { (result, previousPage) }
}

struct MastodonFeedService: FeedService {
    private let client: TootClient
    private let quoteSupport = QuoteSupportCache()

    init(client: TootClient) { self.client = client }

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
            return []   // these load through their own methods, not as posts
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

    static func notification(from n: TootNotification) -> FeedNotification {
        let kind: FeedNotification.Kind
        switch n.type {
        case .mention: kind = .mention
        case .favourite: kind = .like
        case .repost: kind = .repost
        case .follow, .followRequest: kind = .follow
        case .poll: kind = .poll
        case .quote, .quotedUpdate: kind = .quote
        default: kind = .other
        }
        return FeedNotification(
            id: n.id, kind: kind,
            actorName: displayOrHandle(n.account.displayName, n.account.acct),
            actorHandle: "@\(n.account.acct)", actorID: n.account.id,
            avatarURL: URL(string: n.account.avatar),
            emojis: emojiMap(n.account.emojis),
            post: n.post.map { Self.feedPost(from: $0) }, date: n.createdAt)
    }

    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = liked
            ? try await client.favouritePost(id: id)
            : try await client.unfavouritePost(id: id)
        var copy = post
        copy.isLiked = updated.favourited ?? liked
        return copy
    }

    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = reposted
            ? try await client.boostPost(id: id)
            : try await client.unboostPost(id: id)
        var copy = post
        copy.isReposted = updated.reposted ?? reposted
        return copy
    }

    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility: PostVisibility) async throws -> PostedItem {
        guard case .mastodon(let id) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        try TargetLimits().checkImageCount(images.count, for: .mastodon)
        let maxBytes = images.isEmpty ? 0 : await client.mastodonImageByteLimit()
        let mediaIds = try await client.uploadJPEGImages(images, maxBytes: maxBytes)
        // Carry the parent's content warning forward; the caller seeds visibility
        // from the parent so a reply never widens its audience.
        let spoiler = (post.spoilerText?.isEmpty == false) ? post.spoilerText : nil
        var params = PostParams(post: text, visibility: visibility.tootVisibility, spoilerText: spoiler)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        params.inReplyToId = id
        params.sensitive = post.isSensitive
        let posted = try await client.publishPost(params)
        return PostedItem(url: posted.url, ref: .mastodon(statusID: posted.id))
    }

    func quote(post: FeedPost, text: String, visibility: PostVisibility) async throws -> PostedItem {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
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

    /// Whether a server version string advertises quote-post support (4.4+),
    /// or nil when no leading `major.minor` semver can be parsed (forks report
    /// free-form versions; callers proceed best-effort for those).
    static func supportsQuotePosts(version: String) -> Bool? {
        let head = version.prefix { ("0"..."9").contains($0) || $0 == "." }
        let parts = head.split(separator: ".")
        guard let first = parts.first, let major = Int(first) else { return nil }
        let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return major > 4 || (major == 4 && minor >= 4)
    }

    func thread(of post: FeedPost) async throws -> PostThread {
        guard case .mastodon(let id) = post.nativeRef else {
            return PostThread(ancestors: [], descendants: [])
        }
        let context = try await client.getContext(id: id)
        return PostThread(
            ancestors: context.ancestors.map { Self.feedPost(from: $0) },
            descendants: context.descendants.map { Self.feedPost(from: $0) })
    }

    func profile(id: String) async throws -> Profile {
        Self.profile(from: try await client.getAccount(by: id))
    }

    func myProfile() async throws -> Profile {
        Self.profile(from: try await client.verifyCredentials())
    }

    func authorPosts(id: String) async throws -> [FeedPost] {
        try await paged(target: 80, maxPages: 2) {
            try await client.getTimeline(.user(userID: id), pageInfo: $0, limit: 40).page
        }.map { Self.feedPost(from: $0) }
    }

    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        guard case .mastodon(let statusID) = post.nativeRef else { throw FeedError.wrongPlatform }
        try await client.report(ReportParams(
            accountId: post.authorID, category: reason.mastodonCategory,
            postIds: [statusID], comment: comment.nilIfBlank))
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        try await client.report(ReportParams(
            accountId: id, category: reason.mastodonCategory,
            comment: comment.nilIfBlank))
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
            posts: result.posts.map(Self.feedPost(from:)))
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
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        _ = try await client.deletePost(id: id)
    }

    func editableSource(of post: FeedPost) async throws -> EditableSource {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let source = try await client.getPostSource(id: id)
        return EditableSource(text: source.text, spoiler: source.spoilerText)
    }

    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        // Re-attach the post's existing media (and keep its sensitivity) so an
        // edit to the text alone never drops the images.
        let current = try await client.getPost(id: id)
        var params = EditPostParams(post: text)
        params.spoilerText = spoiler.nilIfBlank
        // `current` was just fetched, so its sensitive flag is authoritative;
        // the caller's post may be stale.
        params.sensitive = current.sensitive
        let mediaIds = current.mediaAttachments.map(\.id)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        let updated = try await client.editPost(id: id, params)
        return Self.feedPost(from: updated)
    }

    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = bookmarked
            ? try await client.bookmarkPost(id: id)
            : try await client.unbookmarkPost(id: id)
        var copy = post
        copy.isBookmarked = updated.bookmarked ?? bookmarked
        return copy
    }

    func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        let updated = pinned ? try await client.pinPost(id: id) : try await client.unpinPost(id: id)
        var copy = post
        copy.isPinned = updated.pinned ?? pinned
        return copy
    }

    func likedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case .mastodon(let id) = post.nativeRef else { return [] }
        return try await paged(target: 200, maxPages: 3) {
            try await client.getAccountsFavourited(id: id, $0, limit: 80).page
        }.map { Self.profile(from: $0) }
    }

    func repostedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case .mastodon(let id) = post.nativeRef else { return [] }
        return try await paged(target: 200, maxPages: 3) {
            try await client.getAccountsBoosted(id: id, $0, limit: 80).page
        }.map { Self.profile(from: $0) }
    }

    func conversations(includeHistory: Bool,
                       onPage: @Sendable ([Conversation]) async -> Void) async throws -> [Conversation] {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }
    func messages(in conversationID: String) async throws -> [DirectMessage] {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }
    func sendMessage(_ text: String, to conversationID: String) async throws {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }

    func liveUpdates() async -> AsyncStream<FeedUpdate>? {
        do {
            let stream = try await client.streaming.subscribe(to: .user)
            return AsyncStream { continuation in
                let task = Task {
                    do {
                        for try await event in stream {
                            if let update = Self.feedUpdate(from: event) {
                                continuation.yield(update)
                            }
                        }
                    } catch {
                        Log.feed.error("Mastodon stream failed: \(error)")
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            Log.feed.error("Mastodon stream subscription failed: \(error)")
            return nil
        }
    }

    static func feedUpdate(from event: StreamingClient.Event) -> FeedUpdate? {
        switch event {
        case .connectionUp: return .connected
        case .connectionDown: return .disconnected
        case let .receivedEvent(content):
            return contentUpdate(from: content)
        }
    }

    private static func contentUpdate(from content: EventContent) -> FeedUpdate? {
        switch content {
        case .update: return .home
        case .notification: return .notifications
        case .delete, .postUpdate, .filtersChanged: return .postChanged
        case .conversation, .announcement, .announcementReaction, .announcementDelete,
             .encryptedMessage, .unsupportedEvent: return nil
        }
    }

    func relationship(with id: String) async throws -> AccountRelationship {
        Self.relationship(from: try await client.getRelationships(by: [id]).first)
    }

    func relationships(with ids: [String]) async throws -> [String: AccountRelationship] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: AccountRelationship] = [:]
        for r in try await client.getRelationships(by: ids) {
            guard let id = r.id else { continue }
            result[id] = Self.relationship(from: r)
        }
        return result
    }

    static func relationship(from r: Relationship?) -> AccountRelationship {
        AccountRelationship(isFollowing: r?.following ?? false, isFollowedBy: r?.followedBy ?? false,
                            isMuting: r?.muting ?? false, isBlocking: r?.blocking ?? false)
    }

    func setFollowing(_ following: Bool, for id: String,
                             current: AccountRelationship) async throws -> AccountRelationship {
        Self.relationship(from: following
            ? try await client.followAccount(by: id)
            : try await client.unfollowAccount(by: id))
    }

    func setMuted(_ muted: Bool, for id: String,
                         current: AccountRelationship) async throws -> AccountRelationship {
        Self.relationship(from: muted
            ? try await client.muteAccount(by: id)
            : try await client.unmuteAccount(by: id))
    }

    func setBlocked(_ blocked: Bool, for id: String,
                           current: AccountRelationship) async throws -> AccountRelationship {
        Self.relationship(from: blocked
            ? try await client.blockAccount(by: id)
            : try await client.unblockAccount(by: id))
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

    static func profile(from account: Account) -> Profile {
        Profile(
            id: account.id,
            name: displayOrHandle(account.displayName, account.acct),
            handle: "@\(account.acct)",
            avatarURL: URL(string: account.avatar),
            bannerURL: URL(string: account.header),
            bio: HTMLRenderer.renderAttributed(account.note),
            followers: account.followersCount,
            following: account.followingCount,
            posts: account.postsCount,
            webURL: URL(string: account.url),
            emojis: emojiMap(account.emojis))
    }

    /// Shortcode → static image URL across Mastodon emoji lists; later lists win.
    static func emojiMap(_ lists: [Emoji]...) -> [String: URL] {
        var map: [String: URL] = [:]
        for list in lists {
            for emoji in list {
                if let url = URL(string: emoji.staticUrl) {
                    map[emoji.shortcode] = url
                }
            }
        }
        return map
    }

    /// Map a Mastodon attachment to feed media. Animated GIFs arrive as `gifv`
    /// (a looping MP4) and video as `video`; both play inline. Audio is skipped.
    static func media(from att: MediaAttachment) -> FeedImage? {
        guard let url = URL(string: att.url) else { return nil }
        let previewURL = att.previewUrl.flatMap(URL.init(string:))
        let type = att.type.value
        if type == .image {
            return FeedImage(url: url, previewURL: previewURL, altText: att.description ?? "")
        }
        if type == .gifv || type == .video {
            return FeedImage(
                url: url,
                previewURL: previewURL,
                altText: att.description ?? "",
                kind: .video,
                aspectRatio: att.aspectRatio
            )
        }
        return nil
    }

    static func linkCard(from card: Card?) -> LinkCard? {
        guard let card, let url = URL(string: card.url) else { return nil }
        let provider = card.providerName?.isEmpty == false ? card.providerName! : (url.host ?? "")
        return LinkCard(url: url, title: card.title, description: card.description,
                        imageURL: card.image.flatMap(URL.init(string:)), providerName: provider)
    }

    static func quotedPost(from quote: Quote?) -> QuotedPost? {
        guard let quote, case .post(let quoted)? = quote.quotedPost else { return nil }
        // `quotedPost` is also non-nil when the quoted account is blocked/muted;
        // only render an explicitly accepted quote (or flavors that report no state).
        if let state = quote.state?.value, state != .accepted { return nil }
        let q = quoted.displayPost
        let image = q.mediaAttachments.first { $0.type.value == .image }
        return QuotedPost(
            id: "mastodon:\(q.id)",
            authorName: displayOrHandle(q.account.displayName, q.account.acct),
            authorHandle: "@\(q.account.acct)",
            avatarURL: URL(string: q.account.avatar),
            text: HTMLRenderer.renderAttributed(q.content ?? ""),
            imageURL: image.flatMap {
                $0.previewUrl.flatMap(URL.init(string:)) ?? URL(string: $0.url)
            },
            webURL: q.url.flatMap(URL.init(string:)),
            emojis: emojiMap(q.account.emojis, q.emojis))
    }

    static func feedPost(from post: Post) -> FeedPost {
        // A boost carries its real content in `displayPost` (the reblogged status);
        // render that, and attribute it to the booster.
        let display = post.displayPost
        let boostedBy = post.displayingRepost
            ? displayOrHandle(post.account.displayName, post.account.acct)
            : nil
        let images = display.mediaAttachments.compactMap { Self.media(from: $0) }
        return FeedPost(
            // Identify by the outer timeline entry, not `display.id`: the same status
            // boosted by several people must stay distinct (else ForEach IDs collide
            // and FeedMerge drops boosts). `nativeRef` still targets `display.id`.
            id: "mastodon:\(post.id)",
            target: .mastodon,
            authorName: displayOrHandle(display.account.displayName, display.account.acct),
            authorHandle: "@\(display.account.acct)",
            authorID: display.account.id,
            avatarURL: URL(string: display.account.avatar),
            date: display.createdAt,
            text: HTMLRenderer.renderAttributed(display.content ?? ""),
            images: images,
            card: linkCard(from: display.card),
            quoted: quotedPost(from: display.quote),
            webURL: display.url.flatMap(URL.init(string:)),
            isLiked: display.favourited ?? false,
            isReposted: display.reposted ?? false,
            isBookmarked: display.bookmarked ?? false,
            isPinned: display.pinned ?? false,
            replyCount: display.repliesCount,
            repostCount: display.repostsCount,
            likeCount: display.favouritesCount,
            boostedBy: boostedBy,
            mentionHandles: display.mentions.map { "@\($0.acct)" },
            visibility: display.visibility.rawValue,
            spoilerText: display.spoilerText.nilIfBlank,
            isSensitive: display.sensitive,
            isReply: display.inReplyToId != nil,
            replyToHandle: replyToHandle(of: display),
            emojis: emojiMap(post.account.emojis, display.account.emojis, display.emojis),
            nativeRef: .mastodon(statusID: display.id))
    }

    /// The parent author's "@acct". Mastodon gives only the parent's account id, so
    /// it resolves when that is the author (a thread) or someone the post mentions.
    private static func replyToHandle(of post: Post) -> String? {
        guard let parentID = post.inReplyToAccountId else { return nil }
        if parentID == post.account.id {
            return "@\(post.account.acct)"
        }
        return post.mentions.first { $0.id == parentID }.map { "@\($0.acct)" }
    }
}

enum FeedError: Error, CustomStringConvertible, LocalizedError {
    case wrongPlatform
    case notSupported(String)

    var description: String {
        switch self {
        case .wrongPlatform: return "This action does not apply to this post's platform"
        case .notSupported(let what): return what
        }
    }

    var errorDescription: String? { description }
}

/// Session-scoped cache of the instance's quote-post capability. A reference
/// type so copies of the (struct) service share one verdict, mirroring
/// BlueskyFeedService's OwnDIDCache.
private actor QuoteSupportCache {
    private var supported: Bool?
    func get() -> Bool? { supported }
    func set(_ value: Bool) { supported = value }
}
