import Foundation

/// A link preview card (Mastodon `card`, Bluesky external embed).
public struct LinkCard: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let description: String
    public let imageURL: URL?
    public let providerName: String   // e.g. "nytimes.com"

    public init(url: URL, title: String, description: String,
                imageURL: URL?, providerName: String) {
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.providerName = providerName
    }
}

/// A quoted post embedded in another (Mastodon quote, Bluesky record embed).
/// A lightweight projection — enough to render a nested card and open the original.
public struct QuotedPost: Equatable, Sendable, Identifiable {
    public let id: String
    public let authorName: String
    public let authorHandle: String
    public let avatarURL: URL?
    public let text: AttributedString
    public let imageURL: URL?
    public let webURL: URL?

    public init(id: String, authorName: String, authorHandle: String,
                avatarURL: URL?, text: AttributedString, imageURL: URL?, webURL: URL?) {
        self.id = id
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.avatarURL = avatarURL
        self.text = text
        self.imageURL = imageURL
        self.webURL = webURL
    }
}

/// A user profile: header details for the profile view.
public struct Profile: Sendable, Identifiable {
    public let id: String          // account id (Mastodon) / handle (Bluesky)
    public let target: PostTarget
    public let name: String
    public let handle: String      // "@..."
    public let avatarURL: URL?
    public let bannerURL: URL?
    public let bio: AttributedString
    public var followers: Int
    public let following: Int
    public let posts: Int
    public let webURL: URL?

    public init(id: String, target: PostTarget, name: String, handle: String,
                avatarURL: URL?, bannerURL: URL?, bio: AttributedString,
                followers: Int, following: Int, posts: Int, webURL: URL?) {
        self.id = id
        self.target = target
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.bio = bio
        self.followers = followers
        self.following = following
        self.posts = posts
        self.webURL = webURL
    }
}

/// The viewer's relationship to another account. Record URIs are carried so
/// Bluesky can undo a follow/block (Mastodon acts by account id and leaves them nil).
public struct AccountRelationship: Sendable, Equatable {
    public var isFollowing: Bool
    public var isFollowedBy: Bool
    public var isMuting: Bool
    public var isBlocking: Bool
    public var followRecordURI: String?
    public var blockRecordURI: String?

    public init(isFollowing: Bool = false, isFollowedBy: Bool = false,
                isMuting: Bool = false, isBlocking: Bool = false,
                followRecordURI: String? = nil, blockRecordURI: String? = nil) {
        self.isFollowing = isFollowing
        self.isFollowedBy = isFollowedBy
        self.isMuting = isMuting
        self.isBlocking = isBlocking
        self.followRecordURI = followRecordURI
        self.blockRecordURI = blockRecordURI
    }
}

/// A post's surrounding thread: posts above (ancestors, oldest first) and the
/// replies below it (descendants).
public struct PostThread: Sendable {
    public let ancestors: [FeedPost]
    public let descendants: [FeedPost]

    public init(ancestors: [FeedPost], descendants: [FeedPost]) {
        self.ancestors = ancestors
        self.descendants = descendants
    }
}
