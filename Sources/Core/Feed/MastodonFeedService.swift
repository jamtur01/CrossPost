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
        var params = PostParams(post: text, visibility: .public)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        params.inReplyToId = id
        let posted = try await client.publishPost(params)
        return PostedItem(url: posted.url)
    }

    static func feedPost(from post: Post) -> FeedPost {
        let images = post.mediaAttachments
            .filter { $0.type.value == .image }
            .compactMap { att -> FeedImage? in
                guard let url = URL(string: att.url) else { return nil }
                return FeedImage(url: url, altText: att.description ?? "")
            }
        return FeedPost(
            id: "mastodon:\(post.id)",
            target: .mastodon,
            authorName: post.account.displayName?.isEmpty == false
                ? post.account.displayName!
                : post.account.acct,
            authorHandle: "@\(post.account.acct)",
            avatarURL: URL(string: post.account.avatar),
            date: post.createdAt,
            text: AttributedString(HTMLRenderer.render(post.content ?? "")),
            images: images,
            webURL: post.url.flatMap(URL.init(string:)),
            isLiked: post.favourited ?? false,
            isReposted: post.reposted ?? false,
            nativeRef: .mastodon(statusID: post.id))
    }
}

public enum FeedError: Error, CustomStringConvertible {
    case wrongPlatform
    case notSupported(String)

    public var description: String {
        switch self {
        case .wrongPlatform: return "This action does not apply to this post's platform"
        case .notSupported(let what): return what
        }
    }
}
