import Foundation

struct FeedImage: Identifiable, Equatable, Sendable {
    enum Kind: Sendable, Equatable { case image, gif, video }

    let id: String
    let url: URL             // image URL, or the looping MP4 for a gif/video
    let altText: String
    let kind: Kind
    let aspectRatio: Double?

    init(url: URL, altText: String, kind: Kind = .image,
                aspectRatio: Double? = nil) {
        self.id = url.absoluteString
        self.url = url
        self.altText = altText
        self.kind = kind
        self.aspectRatio = aspectRatio
    }
}

/// A notification event (like, repost, follow, mention, reply, quote) with the
/// actor and, where relevant, the related post.
struct FeedNotification: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case mention, reply, like, repost, follow, quote, poll, other }

    let id: String
    let kind: Kind
    let actorName: String
    let actorHandle: String
    let actorID: String
    let avatarURL: URL?
    let post: FeedPost?     // the related post (the mention/reply, or the liked/reposted subject)
    let date: Date

    init(id: String, kind: Kind, actorName: String, actorHandle: String, actorID: String,
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
enum NativeRef: Equatable, Sendable {
    case mastodon(statusID: String)
    case bluesky(uri: String, cid: String, rootURI: String, rootCID: String)
}

struct FeedPost: Identifiable, Equatable, Sendable {
    let id: String          // "<platform>:<native id>"
    let target: PostTarget
    let authorName: String
    let authorHandle: String
    let authorID: String     // Mastodon account.id / Bluesky DID (for profile + author feed)
    let avatarURL: URL?
    let date: Date
    let text: AttributedString
    let images: [FeedImage]
    let card: LinkCard?      // link preview, if any
    let quoted: QuotedPost?  // quoted post, if any
    let webURL: URL?
    var isLiked: Bool
    var isReposted: Bool
    var isBookmarked: Bool
    var isPinned: Bool
    var replyCount: Int
    var repostCount: Int
    var likeCount: Int
    var likeRecordURI: String?      // Bluesky: like record uri (for undo); nil for Mastodon
    var repostRecordURI: String?    // Bluesky: repost record uri (for undo); nil for Mastodon
    let boostedBy: String?          // display name of the booster/reposter, if this is a boost
    let mentionHandles: [String]    // "@handle"s the parent post mentions (for reply prefill)
    let visibility: String?         // Mastodon visibility (public/unlisted/private/direct); nil for Bluesky
    let spoilerText: String?        // Mastodon content warning, if any
    let isSensitive: Bool           // Mastodon sensitive-media flag
    let isReply: Bool               // this post is itself a reply (has a parent to show)
    let nativeRef: NativeRef

    init(id: String, target: PostTarget, authorName: String, authorHandle: String,
                authorID: String = "",
                avatarURL: URL?, date: Date,
                text: AttributedString, images: [FeedImage],
                card: LinkCard? = nil, quoted: QuotedPost? = nil,
                webURL: URL?, isLiked: Bool, isReposted: Bool,
                isBookmarked: Bool = false, isPinned: Bool = false,
                replyCount: Int = 0, repostCount: Int = 0, likeCount: Int = 0,
                likeRecordURI: String? = nil, repostRecordURI: String? = nil,
                boostedBy: String? = nil, mentionHandles: [String] = [],
                visibility: String? = nil, spoilerText: String? = nil,
                isSensitive: Bool = false, isReply: Bool = false,
                nativeRef: NativeRef) {
        self.id = id; self.target = target; self.authorName = authorName
        self.authorHandle = authorHandle; self.authorID = authorID
        self.avatarURL = avatarURL
        self.date = date
        self.text = text; self.images = images
        self.card = card; self.quoted = quoted; self.webURL = webURL
        self.isLiked = isLiked; self.isReposted = isReposted
        self.isBookmarked = isBookmarked; self.isPinned = isPinned
        self.replyCount = replyCount; self.repostCount = repostCount; self.likeCount = likeCount
        self.likeRecordURI = likeRecordURI; self.repostRecordURI = repostRecordURI
        self.boostedBy = boostedBy; self.mentionHandles = mentionHandles
        self.visibility = visibility; self.spoilerText = spoilerText
        self.isSensitive = isSensitive; self.isReply = isReply
        self.nativeRef = nativeRef
    }
}
