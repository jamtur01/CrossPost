import Foundation

/// The editable source of a post: the raw text and content warning, before the
/// server renders them to HTML/rich text.
struct EditableSource: Sendable, Equatable {
    let text: String
    let spoiler: String
}

/// Results of a search: matching accounts and posts.
struct SearchResults: Sendable, Equatable {
    var accounts: [Profile]
    var posts: [FeedPost]
    var isEmpty: Bool { accounts.isEmpty && posts.isEmpty }

    init(accounts: [Profile] = [], posts: [FeedPost] = []) {
        self.accounts = accounts
        self.posts = posts
    }
}

/// A platform's feed: load posts, toggle like/repost, and reply to one post.
/// `setLiked`/`setReposted` return the updated FeedPost (new flags + record uris).
protocol FeedService: Sendable {
    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost]
    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost
    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost
    /// Reply to a post. `visibility` applies to Mastodon (defaulting to the
    /// parent's, so a reply never widens its audience); Bluesky ignores it.
    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility: PostVisibility) async throws -> PostedItem
    /// Create a quote post embedding `post`, on the post's own network.
    /// `visibility` applies to Mastodon only.
    func quote(post: FeedPost, text: String, visibility: PostVisibility) async throws -> PostedItem
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
    /// Search for accounts and posts matching `query`.
    func search(_ query: String) async throws -> SearchResults
    /// Posts the user has pinned to their profile (Mastodon; empty on Bluesky).
    func pinnedPosts(of id: String) async throws -> [FeedPost]
    /// The signed-in user's bookmarked posts (Mastodon; empty on Bluesky).
    func bookmarkedPosts() async throws -> [FeedPost]
    /// The signed-in user's liked / favourited posts.
    func likedPosts() async throws -> [FeedPost]

    // MARK: Social graph

    /// The viewer's relationship to an account (following, muting, blocking, …).
    func relationship(with id: String) async throws -> AccountRelationship
    /// Batch lookup of the viewer's relationships, keyed by the requested ids.
    /// Lets a notification list resolve follow state in one round-trip per page.
    func relationships(with ids: [String]) async throws -> [String: AccountRelationship]
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
    /// Mark notifications read up to the newest one the user just saw, so a
    /// notification that arrives after the list loaded isn't marked read. Mastodon
    /// uses its id as a read marker; Bluesky uses its timestamp as the seen boundary.
    func markNotificationsRead(upTo latest: FeedNotification?) async throws

    // MARK: Post management & engagement

    /// Delete one of the signed-in user's own posts.
    func deletePost(_ post: FeedPost) async throws
    /// The editable source (raw text + content warning) of your own post.
    /// Mastodon only; Bluesky has no edit and throws.
    func editableSource(of post: FeedPost) async throws -> EditableSource
    /// Submit an edit to your own post; returns the updated post. Mastodon only.
    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost
    /// Bookmark / unbookmark a post; returns the post with its updated flag.
    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost
    /// Pin / unpin one of your own posts (Mastodon; throws on Bluesky).
    func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost
    /// Accounts that liked / reposted a post.
    func likedBy(_ post: FeedPost) async throws -> [Profile]
    func repostedBy(_ post: FeedPost) async throws -> [Profile]
    /// Report a post for moderation, with an optional free-text comment.
    func report(post: FeedPost, reason: ReportReason, comment: String) async throws
    /// Report an account for moderation (`id` = Mastodon account id / Bluesky DID).
    func report(accountID id: String, reason: ReportReason, comment: String) async throws

    // MARK: Direct messages

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
