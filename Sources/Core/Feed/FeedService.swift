import Foundation

/// A platform's feed: load posts, toggle like/repost, and reply to one post.
/// `setLiked`/`setReposted` return the updated FeedPost (new flags + record uris).
public protocol FeedService: Sendable {
    var target: PostTarget { get }
    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost]
    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost
    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost
    func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem
    /// The post this one is replying to, if any (for showing reply context).
    func parent(of post: FeedPost) async throws -> FeedPost?
}
