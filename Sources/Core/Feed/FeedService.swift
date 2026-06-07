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

    // MARK: Notifications

    /// All notifications (mentions, replies, likes, reposts, follows, quotes).
    func notifications() async throws -> [FeedNotification]
    /// Count of unread notifications, for the tab badge.
    func unreadNotificationCount() async throws -> Int
    /// Mark notifications as read (clears the unread count).
    func markNotificationsRead() async throws

    // MARK: Post management & engagement

    /// Delete one of the signed-in user's own posts.
    func deletePost(_ post: FeedPost) async throws
    /// Bookmark / unbookmark a post; returns the post with its updated flag.
    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost
    /// Pin / unpin one of your own posts (Mastodon; throws on Bluesky).
    func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost
    /// Accounts that liked / reposted a post.
    func likedBy(_ post: FeedPost) async throws -> [Profile]
    func repostedBy(_ post: FeedPost) async throws -> [Profile]

    // MARK: Direct messages

    /// Whether this platform supports direct messages in the app.
    var supportsDirectMessages: Bool { get }
    /// The user's DM conversations.
    func conversations() async throws -> [Conversation]
    /// Messages in a conversation, oldest first.
    func messages(in conversationID: String) async throws -> [DirectMessage]
    /// Send a message to a conversation.
    func sendMessage(_ text: String, to conversationID: String) async throws

    // MARK: Real-time

    /// A stream that yields whenever the server signals a change, for live refresh.
    /// Returns nil if the platform has no usable per-user stream (Bluesky uses polling).
    func liveUpdates() async -> AsyncStream<Void>?
}
