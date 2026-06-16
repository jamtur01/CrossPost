import Foundation
@testable import CrossPost

/// A configurable in-memory `FeedService` for model tests: returns canned data,
/// records calls, and never touches the network. Tests drive it on the main actor,
/// so the unsynchronised mutable state is safe.
final class FakeFeedService: FeedService, @unchecked Sendable {
    enum FakeError: Error { case boom }

    // Canned responses.
    var feed: [FeedPost] = []
    var notificationsToReturn: [FeedNotification] = []
    var unread = 0

    // Failure toggles.
    var failLoad = false
    var failLike = false
    var failRepost = false
    var failDelete = false

    // Recorded calls.
    private(set) var markedReadCalls: [FeedNotification?] = []
    private(set) var deletedIDs: [String] = []
    private(set) var loadFeedCalls = 0

    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        loadFeedCalls += 1
        if failLoad { throw FakeError.boom }
        return feed
    }

    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        if failLike { throw FakeError.boom }
        var copy = post
        copy.isLiked = liked
        copy.likeRecordURI = liked ? "at://like/\(post.id)" : nil
        return copy
    }

    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        if failRepost { throw FakeError.boom }
        var copy = post
        copy.isReposted = reposted
        copy.repostRecordURI = reposted ? "at://repost/\(post.id)" : nil
        return copy
    }

    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility: PostVisibility) async throws -> PostedItem {
        PostedItem(url: "https://example/reply")
    }
    func thread(of post: FeedPost) async throws -> PostThread { PostThread(ancestors: [], descendants: []) }
    func profile(id: String) async throws -> Profile { Self.profile(id) }
    func profile(forURL url: URL) async throws -> Profile? { nil }
    func myProfile() async throws -> Profile { Self.profile("me") }
    func authorPosts(id: String) async throws -> [FeedPost] { feed }
    func pinnedPosts(of id: String) async throws -> [FeedPost] { [] }
    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {}
    func report(accountID id: String, reason: ReportReason, comment: String) async throws {}

    var relationshipsToReturn: [String: AccountRelationship] = [:]
    private(set) var relationshipsRequests: [[String]] = []

    func relationship(with id: String) async throws -> AccountRelationship {
        relationshipsToReturn[id] ?? AccountRelationship()
    }
    func relationships(with ids: [String]) async throws -> [String: AccountRelationship] {
        relationshipsRequests.append(ids)
        return relationshipsToReturn.filter { ids.contains($0.key) }
    }
    func setFollowing(_ following: Bool, for id: String,
                      current: AccountRelationship) async throws -> AccountRelationship {
        setFollowingCalls.append("\(id):\(following)")
        var copy = current; copy.isFollowing = following; return copy
    }
    private(set) var setFollowingCalls: [String] = []
    func setMuted(_ muted: Bool, for id: String,
                  current: AccountRelationship) async throws -> AccountRelationship {
        var copy = current; copy.isMuting = muted; return copy
    }
    func setBlocked(_ blocked: Bool, for id: String,
                    current: AccountRelationship) async throws -> AccountRelationship {
        var copy = current; copy.isBlocking = blocked; return copy
    }
    func followers(of id: String) async throws -> [Profile] { [] }
    func following(of id: String) async throws -> [Profile] { [] }

    func notifications() async throws -> [FeedNotification] { notificationsToReturn }
    func unreadNotificationCount() async throws -> Int { unread }
    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        markedReadCalls.append(latest)
    }

    func deletePost(_ post: FeedPost) async throws {
        deletedIDs.append(post.id)
        if failDelete { throw FakeError.boom }
    }
    private(set) var bookmarkSetCalls: [Bool] = []
    private(set) var pinSetCalls: [Bool] = []
    func setBookmarked(_ bookmarked: Bool, on post: FeedPost) async throws -> FeedPost {
        bookmarkSetCalls.append(bookmarked)
        var copy = post; copy.isBookmarked = bookmarked; return copy
    }
    func setPinned(_ pinned: Bool, on post: FeedPost) async throws -> FeedPost {
        pinSetCalls.append(pinned)
        var copy = post; copy.isPinned = pinned; return copy
    }
    func likedBy(_ post: FeedPost) async throws -> [Profile] { [] }
    func repostedBy(_ post: FeedPost) async throws -> [Profile] { [] }

    func conversations() async throws -> [Conversation] { [] }
    func messages(in conversationID: String) async throws -> [DirectMessage] { [] }
    func sendMessage(_ text: String, to conversationID: String) async throws {}

    func liveUpdates() async -> AsyncStream<Void>? { nil }

    private static func profile(_ id: String) -> Profile {
        Profile(id: id, name: id, handle: "@\(id)", avatarURL: nil, bannerURL: nil,
                bio: AttributedString(""), followers: 0, following: 0, posts: 0, webURL: nil)
    }
}

extension FeedNotification {
    /// A minimal notification fixture for model tests.
    static func fixture(id: String, date: Date, actorID: String = "a") -> FeedNotification {
        FeedNotification(id: id, kind: .like, actorName: "A", actorHandle: "@a", actorID: actorID,
                         avatarURL: nil, post: nil, date: date)
    }
}
