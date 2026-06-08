import Foundation

/// A link preview card (Mastodon `card`, Bluesky external embed).
struct LinkCard: Equatable, Sendable {
    let url: URL
    let title: String
    let description: String
    let imageURL: URL?
    let providerName: String   // e.g. "nytimes.com"

    init(url: URL, title: String, description: String,
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
struct QuotedPost: Equatable, Sendable, Identifiable {
    let id: String
    let authorName: String
    let authorHandle: String
    let avatarURL: URL?
    let text: AttributedString
    let imageURL: URL?
    let webURL: URL?

    init(id: String, authorName: String, authorHandle: String,
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
struct Profile: Sendable, Identifiable {
    let id: String          // account id (Mastodon) / handle (Bluesky)
    let name: String
    let handle: String      // "@..."
    let avatarURL: URL?
    let bannerURL: URL?
    let bio: AttributedString
    var followers: Int
    let following: Int
    let posts: Int
    let webURL: URL?

    init(id: String, name: String, handle: String,
                avatarURL: URL?, bannerURL: URL?, bio: AttributedString,
                followers: Int, following: Int, posts: Int, webURL: URL?) {
        self.id = id
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
struct AccountRelationship: Sendable, Equatable {
    var isFollowing: Bool
    var isFollowedBy: Bool
    var isMuting: Bool
    var isBlocking: Bool
    var followRecordURI: String?
    var blockRecordURI: String?

    init(isFollowing: Bool = false, isFollowedBy: Bool = false,
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
struct PostThread: Sendable {
    let ancestors: [FeedPost]
    let descendants: [FeedPost]

    init(ancestors: [FeedPost], descendants: [FeedPost]) {
        self.ancestors = ancestors
        self.descendants = descendants
    }
}
