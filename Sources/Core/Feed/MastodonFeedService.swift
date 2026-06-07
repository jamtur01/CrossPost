import Foundation
import TootSDK

public struct MastodonFeedService: FeedService {
    public let target: PostTarget = .mastodon
    private let client: TootClient

    public init(client: TootClient) { self.client = client }

    public func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let posts = try await client.getTimeline(.home).result
            return posts.map { Self.feedPost(from: $0) }
        case .notifications, .messages:
            return []   // these load through their own methods, not as posts
        }
    }

    public func notifications() async throws -> [FeedNotification] {
        try await client.getNotifications(limit: 40).result.map { Self.notification(from: $0) }
    }

    public func unreadNotificationCount() async throws -> Int {
        try await client.getNotificationsUnreadCount()
    }

    public func markNotificationsRead(upTo latestID: String?) async throws {
        guard let latestID else { return }
        _ = try await client.updateMarkers(notificationsLastReadId: latestID)
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
            actorName: n.account.displayName?.isEmpty == false ? n.account.displayName! : n.account.acct,
            actorHandle: "@\(n.account.acct)", actorID: n.account.id,
            avatarURL: URL(string: n.account.avatar),
            post: n.post.map { Self.feedPost(from: $0) }, date: n.createdAt)
    }

    public func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { return post }
        let updated = liked
            ? try await client.favouritePost(id: id)
            : try await client.unfavouritePost(id: id)
        var copy = post
        copy.isLiked = updated.favourited ?? liked
        return copy
    }

    public func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { return post }
        let updated = reposted
            ? try await client.boostPost(id: id)
            : try await client.unboostPost(id: id)
        var copy = post
        copy.isReposted = updated.reposted ?? reposted
        return copy
    }

    public func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem {
        guard case .mastodon(let id) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        guard images.count <= TargetLimits.imageMax else {
            throw MediaValidationError.tooManyImages(target: .mastodon,
                                                     count: images.count,
                                                     limit: TargetLimits.imageMax)
        }
        var mediaIds: [String] = []
        let maxBytes = images.isEmpty ? 0 : await client.mastodonImageByteLimit()
        for image in images {
            let jpeg = try ImageProcessor.jpegUnderBudget(image.imageData, maxBytes: maxBytes)
            let params = UploadMediaAttachmentParams(
                file: jpeg,
                thumbnail: nil,
                description: image.altText.isEmpty ? nil : image.altText,
                focus: nil)
            mediaIds.append(try await client.uploadMedia(params, mimeType: "image/jpeg").id)
        }
        // Inherit the parent's visibility (a public reply to a private post would
        // leak it) and its content warning. Default to unlisted if unknown.
        let visibility = post.visibility.flatMap(Post.Visibility.init(rawValue:)) ?? .unlisted
        let spoiler = (post.spoilerText?.isEmpty == false) ? post.spoilerText : nil
        var params = PostParams(post: text, visibility: visibility, spoilerText: spoiler)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        params.inReplyToId = id
        params.sensitive = post.isSensitive
        let posted = try await client.publishPost(params)
        return PostedItem(url: posted.url)
    }

    public func thread(of post: FeedPost) async throws -> PostThread {
        guard case .mastodon(let id) = post.nativeRef else {
            return PostThread(ancestors: [], descendants: [])
        }
        let context = try await client.getContext(id: id)
        return PostThread(
            ancestors: context.ancestors.map { Self.feedPost(from: $0) },
            descendants: context.descendants.map { Self.feedPost(from: $0) })
    }

    public func profile(id: String) async throws -> Profile {
        Self.profile(from: try await client.getAccount(by: id))
    }

    public func myProfile() async throws -> Profile {
        Self.profile(from: try await client.verifyCredentials())
    }

    public func authorPosts(id: String) async throws -> [FeedPost] {
        try await client.getTimeline(.user(userID: id)).result.map { Self.feedPost(from: $0) }
    }

    public func deletePost(_ post: FeedPost) async throws {
        guard case .mastodon(let id) = post.nativeRef else { throw FeedError.wrongPlatform }
        _ = try await client.deletePost(id: id)
    }

    public func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { return post }
        let updated = bookmarked
            ? try await client.bookmarkPost(id: id)
            : try await client.unbookmarkPost(id: id)
        var copy = post
        copy.isBookmarked = updated.bookmarked ?? bookmarked
        return copy
    }

    public func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { return post }
        let updated = pinned ? try await client.pinPost(id: id) : try await client.unpinPost(id: id)
        var copy = post
        copy.isPinned = updated.pinned ?? pinned
        return copy
    }

    public func likedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case .mastodon(let id) = post.nativeRef else { return [] }
        return try await client.getAccountsFavourited(id: id).result.map { Self.profile(from: $0) }
    }

    public func repostedBy(_ post: FeedPost) async throws -> [Profile] {
        guard case .mastodon(let id) = post.nativeRef else { return [] }
        return try await client.getAccountsBoosted(id: id).result.map { Self.profile(from: $0) }
    }

    public var supportsDirectMessages: Bool { false }
    public func conversations() async throws -> [Conversation] {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }
    public func messages(in conversationID: String) async throws -> [DirectMessage] {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }
    public func sendMessage(_ text: String, to conversationID: String) async throws {
        throw FeedError.notSupported("Direct messages aren't supported for Mastodon yet.")
    }

    public func liveUpdates() async -> AsyncStream<Void>? {
        guard let socket = try? await client.beginStreaming() else { return nil }
        try? await socket.sendQuery(StreamQuery(.subscribe, timeline: .user))
        return AsyncStream { continuation in
            let task = Task {
                // Each streamed event (status, notification, delete) is a signal to
                // refresh; we don't read the event content, just that it happened.
                do {
                    for try await _ in socket.stream { continuation.yield(()) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                socket.close()
            }
        }
    }

    public func relationship(with id: String) async throws -> AccountRelationship {
        Self.relationship(from: try await client.getRelationships(by: [id]).first)
    }

    static func relationship(from r: Relationship?) -> AccountRelationship {
        AccountRelationship(isFollowing: r?.following ?? false, isFollowedBy: r?.followedBy ?? false,
                            isMuting: r?.muting ?? false, isBlocking: r?.blocking ?? false)
    }

    public func setFollowing(_ following: Bool, for id: String,
                             current: AccountRelationship) async throws -> AccountRelationship {
        Self.relationship(from: following
            ? try await client.followAccount(by: id)
            : try await client.unfollowAccount(by: id))
    }

    public func setMuted(_ muted: Bool, for id: String,
                         current: AccountRelationship) async throws -> AccountRelationship {
        Self.relationship(from: muted
            ? try await client.muteAccount(by: id)
            : try await client.unmuteAccount(by: id))
    }

    public func setBlocked(_ blocked: Bool, for id: String,
                           current: AccountRelationship) async throws -> AccountRelationship {
        Self.relationship(from: blocked
            ? try await client.blockAccount(by: id)
            : try await client.unblockAccount(by: id))
    }

    public func followers(of id: String) async throws -> [Profile] {
        try await client.getFollowers(for: id).result.map { Self.profile(from: $0) }
    }

    public func following(of id: String) async throws -> [Profile] {
        try await client.getFollowing(for: id).result.map { Self.profile(from: $0) }
    }

    public func profile(forURL url: URL) async throws -> Profile? {
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
            target: .mastodon,
            name: account.displayName?.isEmpty == false ? account.displayName! : account.acct,
            handle: "@\(account.acct)",
            avatarURL: URL(string: account.avatar),
            bannerURL: URL(string: account.header),
            bio: HTMLRenderer.renderAttributed(account.note),
            followers: account.followersCount,
            following: account.followingCount,
            posts: account.postsCount,
            webURL: URL(string: account.url))
    }

    /// Map a Mastodon attachment to feed media. Animated GIFs arrive as `gifv`
    /// (a looping MP4) and video as `video`; both play inline. Audio is skipped.
    static func media(from att: MediaAttachment) -> FeedImage? {
        guard let url = URL(string: att.url) else { return nil }
        let type = att.type.value
        if type == .image {
            return FeedImage(url: url, altText: att.description ?? "")
        }
        if type == .gifv || type == .video {
            return FeedImage(url: url, altText: att.description ?? "", kind: .video,
                             previewURL: att.previewUrl.flatMap(URL.init(string:)),
                             aspectRatio: att.aspectRatio)
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
        let q = quoted.displayPost
        let image = q.mediaAttachments.first { $0.type.value == .image }
        return QuotedPost(
            id: "mastodon:\(q.id)",
            authorName: q.account.displayName?.isEmpty == false ? q.account.displayName! : q.account.acct,
            authorHandle: "@\(q.account.acct)",
            avatarURL: URL(string: q.account.avatar),
            text: HTMLRenderer.renderAttributed(q.content ?? ""),
            imageURL: image.flatMap { URL(string: $0.url) },
            webURL: q.url.flatMap(URL.init(string:)))
    }

    static func feedPost(from post: Post) -> FeedPost {
        // A boost carries its real content in `displayPost` (the reblogged status);
        // render that, and attribute it to the booster.
        let display = post.displayPost
        let boostedBy = post.displayingRepost
            ? (post.account.displayName?.isEmpty == false ? post.account.displayName! : post.account.acct)
            : nil
        let images = display.mediaAttachments.compactMap { Self.media(from: $0) }
        return FeedPost(
            // Identify by the outer timeline entry, not `display.id`: the same status
            // boosted by several people must stay distinct (else ForEach IDs collide
            // and FeedMerge drops boosts). `nativeRef` still targets `display.id`.
            id: "mastodon:\(post.id)",
            target: .mastodon,
            authorName: display.account.displayName?.isEmpty == false
                ? display.account.displayName!
                : display.account.acct,
            authorHandle: "@\(display.account.acct)",
            authorID: display.account.id,
            avatarURL: URL(string: display.account.avatar),
            authorURL: URL(string: display.account.url),
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
            spoilerText: display.spoilerText.isEmpty ? nil : display.spoilerText,
            isSensitive: display.sensitive,
            isReply: display.inReplyToId != nil,
            nativeRef: .mastodon(statusID: display.id))
    }
}

public enum FeedError: Error, CustomStringConvertible, LocalizedError {
    case wrongPlatform
    case notSupported(String)

    public var description: String {
        switch self {
        case .wrongPlatform: return "This action does not apply to this post's platform"
        case .notSupported(let what): return what
        }
    }

    public var errorDescription: String? { description }
}
