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
        case .mentions:
            let notifications = try await client.getNotifications(params: .init(types: [.mention])).result
            return notifications.compactMap { $0.post.map { Self.feedPost(from: $0) } }
        }
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
        var mediaIds: [String] = []
        for image in images {
            let params = UploadMediaAttachmentParams(
                file: image.imageData,
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
            text: AttributedString(HTMLRenderer.render(q.content ?? "")),
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
        let images = display.mediaAttachments
            .filter { $0.type.value == .image }
            .compactMap { att -> FeedImage? in
                guard let url = URL(string: att.url) else { return nil }
                return FeedImage(url: url, altText: att.description ?? "")
            }
        return FeedPost(
            id: "mastodon:\(display.id)",
            target: .mastodon,
            authorName: display.account.displayName?.isEmpty == false
                ? display.account.displayName!
                : display.account.acct,
            authorHandle: "@\(display.account.acct)",
            avatarURL: URL(string: display.account.avatar),
            authorURL: URL(string: display.account.url),
            date: display.createdAt,
            text: AttributedString(HTMLRenderer.render(display.content ?? "")),
            images: images,
            card: linkCard(from: display.card),
            quoted: quotedPost(from: display.quote),
            webURL: display.url.flatMap(URL.init(string:)),
            isLiked: display.favourited ?? false,
            isReposted: display.reposted ?? false,
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
