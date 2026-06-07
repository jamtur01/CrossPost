import Foundation

/// A platform's feed: load posts, toggle like/repost, and reply to one post.
/// `setLiked`/`setReposted` return the updated FeedPost (new flags + record uris).
public protocol FeedService: Sendable {
    var target: PostTarget { get }
    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost]
    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost
    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost
    func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem
    /// The surrounding thread (ancestors + replies) for the post's detail view.
    func thread(of post: FeedPost) async throws -> PostThread
    /// Profile details for a user (`id` = Mastodon account id / Bluesky handle).
    func profile(id: String) async throws -> Profile
    /// Resolve a profile/mention web link to its profile, or nil if the URL is not
    /// a profile on this platform. Lets mention links open in-app, not the browser.
    func profile(forURL url: URL) async throws -> Profile?
    /// The signed-in user's own profile.
    func myProfile() async throws -> Profile
    /// Recent posts authored by a user.
    func authorPosts(id: String) async throws -> [FeedPost]

    // MARK: Social graph

    /// The viewer's relationship to an account (following, muting, blocking, …).
    func relationship(with id: String) async throws -> AccountRelationship
    /// Follow / unfollow. The current relationship carries any record URI needed to undo.
    func setFollowing(_ following: Bool, for id: String,
                      current: AccountRelationship) async throws -> AccountRelationship
    func setMuted(_ muted: Bool, for id: String,
                  current: AccountRelationship) async throws -> AccountRelationship
    func setBlocked(_ blocked: Bool, for id: String,
                    current: AccountRelationship) async throws -> AccountRelationship
    /// Accounts following / followed by a user.
    func followers(of id: String) async throws -> [Profile]
    func following(of id: String) async throws -> [Profile]
}
