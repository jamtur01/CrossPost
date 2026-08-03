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
    private(set) var quoteCalls: [(text: String, visibility: PostVisibility)] = []
    private(set) var editCalls: [(text: String, spoiler: String)] = []
    private(set) var reportPostCalls: [(reason: ReportReason, comment: String)] = []
    private(set) var reportAccountCalls: [(id: String, reason: ReportReason, comment: String)] = []

    var loadDelay: (() async -> Void)?
    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        loadFeedCalls += 1
        if let loadDelay { await loadDelay() }
        if failLoad { throw FakeError.boom }
        return feed
    }

    private(set) var likeSetCalls: [Bool] = []
    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        likeSetCalls.append(liked)
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

    private(set) var replyVisibilities: [PostVisibility] = []
    func reply(to post: FeedPost, text: String, images: [Attachment],
               visibility: PostVisibility) async throws -> PostedItem {
        replyVisibilities.append(visibility)
        return PostedItem(url: "https://example/reply")
    }
    func quote(
        post: FeedPost,
        text: String,
        visibility: PostVisibility
    ) async throws -> PostedItem {
        quoteCalls.append((text, visibility))
        return PostedItem(url: "https://example/quote")
    }
    func thread(of post: FeedPost) async throws -> PostThread {
        PostThread(ancestors: [], descendants: [])
    }
    func profile(id: String) async throws -> Profile {
        if failLoad { throw FakeError.boom }
        return Self.profile(id)
    }
    var profileForURLResult: Profile?
    var profileForURLDelay: (() async -> Void)?
    private(set) var profileForURLCompletions = 0
    func profile(forURL url: URL) async throws -> Profile? {
        if let profileForURLDelay { await profileForURLDelay() }
        profileForURLCompletions += 1
        return profileForURLResult
    }
    func myProfile() async throws -> Profile { Self.profile("me") }
    func authorPosts(id: String) async throws -> [FeedPost] {
        if failLoad { throw FakeError.boom }
        return feed
    }
    func pinnedPosts(of id: String) async throws -> [FeedPost] { feed.filter(\.isPinned) }

    var searchResultsToReturn = SearchResults()
    private(set) var searchQueries: [String] = []
    func search(_ query: String) async throws -> SearchResults {
        searchQueries.append(query)
        if failLoad { throw FakeError.boom }
        return searchResultsToReturn
    }
    func bookmarkedPosts() async throws -> [FeedPost] { feed.filter(\.isBookmarked) }
    func likedPosts() async throws -> [FeedPost] { feed.filter(\.isLiked) }
    func editableSource(of post: FeedPost) async throws -> EditableSource {
        EditableSource(text: String(post.text.characters), spoiler: post.spoilerText ?? "")
    }
    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        editCalls.append((text, spoiler))
        return post
    }
    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        reportPostCalls.append((reason, comment))
    }
    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        reportAccountCalls.append((id, reason, comment))
    }

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

    private(set) var notificationsCalls = 0
    func notifications() async throws -> [FeedNotification] {
        notificationsCalls += 1
        return notificationsToReturn
    }
    private(set) var unreadCountCalls = 0
    func unreadNotificationCount() async throws -> Int {
        unreadCountCalls += 1
        return unread
    }
    var failMarkRead = false
    /// Awaited after the call is recorded — lets a test suspend the read-mark
    /// mid-flight to stage a tab-switch race deterministically.
    var markReadDelay: (() async -> Void)?
    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        markedReadCalls.append(latest)
        if let markReadDelay { await markReadDelay() }
        if failMarkRead { throw FakeError.boom }
    }

    /// Awaited after the call is recorded — lets a test hold a delete in flight
    /// while it simulates a concurrent poll merge.
    var deleteDelay: (() async -> Void)?
    private(set) var deleteCompletions = 0
    func deletePost(_ post: FeedPost) async throws {
        deletedIDs.append(post.id)
        if let deleteDelay { await deleteDelay() }
        deleteCompletions += 1
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

    var liveStream: AsyncStream<Void>?
    private(set) var liveUpdatesCalls = 0
    func liveUpdates() async -> AsyncStream<Void>? {
        liveUpdatesCalls += 1
        return liveStream
    }

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

/// Suspends async work until the test releases it, so cancellation and delete/poll
/// races can be staged deterministically.
@MainActor
final class TestGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0
    func wait() async {
        arrivals += 1
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
