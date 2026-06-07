import Foundation

public struct FeedImage: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case image, gif, video }

    public let id: String
    public let url: URL             // image URL, or the looping MP4 for a gif/video
    public let previewURL: URL?     // static poster for a gif/video
    public let altText: String
    public let kind: Kind
    public let aspectRatio: Double?

    public init(url: URL, altText: String, kind: Kind = .image,
                previewURL: URL? = nil, aspectRatio: Double? = nil) {
        self.id = url.absoluteString
        self.url = url
        self.previewURL = previewURL
        self.altText = altText
        self.kind = kind
        self.aspectRatio = aspectRatio
    }
}

/// A notification event (like, repost, follow, mention, reply, quote) with the
/// actor and, where relevant, the related post.
public struct FeedNotification: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case mention, reply, like, repost, follow, quote, poll, other }

    public let id: String
    public let kind: Kind
    public let actorName: String
    public let actorHandle: String
    public let actorID: String
    public let avatarURL: URL?
    public let post: FeedPost?     // the related post (the mention/reply, or the liked/reposted subject)
    public let date: Date

    public init(id: String, kind: Kind, actorName: String, actorHandle: String, actorID: String,
                avatarURL: URL?, post: FeedPost?, date: Date) {
        self.id = id
        self.kind = kind
        self.actorName = actorName
        self.actorHandle = actorHandle
        self.actorID = actorID
        self.avatarURL = avatarURL
        self.post = post
        self.date = date
    }
}

/// Platform-native handles needed to act on or reply to a post, as plain values
/// so FeedPost never imports an SDK type.
public enum NativeRef: Equatable, Sendable {
    case mastodon(statusID: String)
    case bluesky(uri: String, cid: String, rootURI: String, rootCID: String)
}

public struct FeedPost: Identifiable, Equatable, Sendable {
    public let id: String          // "<platform>:<native id>"
    public let target: PostTarget
    public let authorName: String
    public let authorHandle: String
    public let authorID: String     // Mastodon account.id / Bluesky handle (for profile + author feed)
    public let avatarURL: URL?
    public let authorURL: URL?      // profile page
    public let date: Date
    public let text: AttributedString
    public let images: [FeedImage]
    public let card: LinkCard?      // link preview, if any
    public let quoted: QuotedPost?  // quoted post, if any
    public let webURL: URL?
    public var isLiked: Bool
    public var isReposted: Bool
    public var replyCount: Int
    public var repostCount: Int
    public var likeCount: Int
    public var likeRecordURI: String?      // Bluesky: like record uri (for undo); nil for Mastodon
    public var repostRecordURI: String?    // Bluesky: repost record uri (for undo); nil for Mastodon
    public let boostedBy: String?          // display name of the booster/reposter, if this is a boost
    public let mentionHandles: [String]    // "@handle"s the parent post mentions (for reply prefill)
    public let visibility: String?         // Mastodon visibility (public/unlisted/private/direct); nil for Bluesky
    public let spoilerText: String?        // Mastodon content warning, if any
    public let isSensitive: Bool           // Mastodon sensitive-media flag
    public let isReply: Bool               // this post is itself a reply (has a parent to show)
    public let nativeRef: NativeRef

    public init(id: String, target: PostTarget, authorName: String, authorHandle: String,
                authorID: String = "",
                avatarURL: URL?, authorURL: URL? = nil, date: Date,
                text: AttributedString, images: [FeedImage],
                card: LinkCard? = nil, quoted: QuotedPost? = nil,
                webURL: URL?, isLiked: Bool, isReposted: Bool,
                replyCount: Int = 0, repostCount: Int = 0, likeCount: Int = 0,
                likeRecordURI: String? = nil, repostRecordURI: String? = nil,
                boostedBy: String? = nil, mentionHandles: [String] = [],
                visibility: String? = nil, spoilerText: String? = nil,
                isSensitive: Bool = false, isReply: Bool = false,
                nativeRef: NativeRef) {
        self.id = id; self.target = target; self.authorName = authorName
        self.authorHandle = authorHandle; self.authorID = authorID
        self.avatarURL = avatarURL
        self.authorURL = authorURL; self.date = date
        self.text = text; self.images = images
        self.card = card; self.quoted = quoted; self.webURL = webURL
        self.isLiked = isLiked; self.isReposted = isReposted
        self.replyCount = replyCount; self.repostCount = repostCount; self.likeCount = likeCount
        self.likeRecordURI = likeRecordURI; self.repostRecordURI = repostRecordURI
        self.boostedBy = boostedBy; self.mentionHandles = mentionHandles
        self.visibility = visibility; self.spoilerText = spoilerText
        self.isSensitive = isSensitive; self.isReply = isReply
        self.nativeRef = nativeRef
    }
}
