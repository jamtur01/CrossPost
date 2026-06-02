import Foundation

public struct FeedImage: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let altText: String

    public init(url: URL, altText: String) {
        self.id = url.absoluteString
        self.url = url
        self.altText = altText
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
    public let avatarURL: URL?
    public let date: Date
    public let text: AttributedString
    public let images: [FeedImage]
    public let webURL: URL?
    public var isLiked: Bool
    public var isReposted: Bool
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
                avatarURL: URL?, date: Date, text: AttributedString, images: [FeedImage],
                webURL: URL?, isLiked: Bool, isReposted: Bool,
                likeRecordURI: String? = nil, repostRecordURI: String? = nil,
                boostedBy: String? = nil, mentionHandles: [String] = [],
                visibility: String? = nil, spoilerText: String? = nil,
                isSensitive: Bool = false, isReply: Bool = false,
                nativeRef: NativeRef) {
        self.id = id; self.target = target; self.authorName = authorName
        self.authorHandle = authorHandle; self.avatarURL = avatarURL; self.date = date
        self.text = text; self.images = images; self.webURL = webURL
        self.isLiked = isLiked; self.isReposted = isReposted
        self.likeRecordURI = likeRecordURI; self.repostRecordURI = repostRecordURI
        self.boostedBy = boostedBy; self.mentionHandles = mentionHandles
        self.visibility = visibility; self.spoilerText = spoilerText
        self.isSensitive = isSensitive; self.isReply = isReply
        self.nativeRef = nativeRef
    }
}
