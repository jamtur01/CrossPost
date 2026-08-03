@testable import CrossPost
import Foundation

/// A configurable in-memory `FeedService` for model tests: returns canned data,
/// records calls, and never touches the network. Tests drive it on the main actor,
/// so the unsynchronised mutable state is safe.
final class FakeFeedService: FeedService, @unchecked Sendable {
    enum FakeError: Error { case boom }

    struct ReportAccountCall: Equatable {
        let id: String
        let reason: ReportReason
        let comment: String
    }

    // Canned responses.
    var feed: [FeedPost] = []
    var notificationsToReturn: [FeedNotification] = []
    var unread = 0
    var conversationsToReturn: [Conversation] = []
    var messagesToReturn: [DirectMessage] = []

    // Failure toggles.
    var failLoad = false
    var failLike = false
    var failRepost = false
    var failDelete = false
    var failPinnedPosts = false
    var failRelationship = false
    var failConversations = false
    var failMessages = false
    var failUnread = false
    var failSendMessage = false

    // Recorded calls.
    private(set) var markedReadCalls: [FeedNotification?] = []
    private(set) var deletedIDs: [String] = []
    private(set) var loadFeedCalls = 0
    private(set) var quoteCalls: [(text: String, visibility: PostVisibility)] = []
    private(set) var editCalls: [(text: String, spoiler: String)] = []
    private(set) var reportPostCalls: [(reason: ReportReason, comment: String)] = []
    private(set) var reportAccountCalls: [ReportAccountCall] = []

    var loadDelay: (() async -> Void)?
    func loadFeed(_: FeedKind) async throws -> [FeedPost] {
        loadFeedCalls += 1
        if let loadDelay {
            await loadDelay()
        }
        if failLoad {
            throw FakeError.boom
        }
        return feed
    }

    private(set) var likeSetCalls: [Bool] = []
    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        likeSetCalls.append(liked)
        if failLike {
            throw FakeError.boom
        }
        var copy = post
        copy.isLiked = liked
        copy.likeRecordURI = liked ? "at://like/\(post.id)" : nil
        return copy
    }

    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        if failRepost {
            throw FakeError.boom
        }
        var copy = post
        copy.isReposted = reposted
        copy.repostRecordURI = reposted ? "at://repost/\(post.id)" : nil
        return copy
    }

    private(set) var replyVisibilities: [PostVisibility] = []
    var replyDelay: (() async -> Void)?
    private(set) var replyCompletions = 0
    func reply(
        to _: FeedPost,
        text _: String,
        images _: [Attachment],
        visibility: PostVisibility
    ) async throws -> PostedItem {
        replyVisibilities.append(visibility)
        if let replyDelay {
            await replyDelay()
        }
        replyCompletions += 1
        return PostedItem(url: "https://example/reply")
    }

    func quote(
        post _: FeedPost,
        text: String,
        visibility: PostVisibility
    ) async throws -> PostedItem {
        quoteCalls.append((text, visibility))
        return PostedItem(url: "https://example/quote")
    }

    func thread(of _: FeedPost) async throws -> PostThread {
        PostThread(ancestors: [], descendants: [])
    }

    private(set) var profileRequests: [String] = []
    func profile(id: String) async throws -> Profile {
        profileRequests.append(id)
        if failLoad {
            throw FakeError.boom
        }
        return Self.profile(id)
    }

    var profileForURLResult: Profile?
    var profileForURLDelay: (() async -> Void)?
    var failProfileForURL = false
    private(set) var profileForURLCompletions = 0
    func profile(forURL _: URL) async throws -> Profile? {
        if let profileForURLDelay {
            await profileForURLDelay()
        }
        if failProfileForURL {
            throw FakeError.boom
        }
        profileForURLCompletions += 1
        return profileForURLResult
    }

    func myProfile() async throws -> Profile {
        Self.profile("me")
    }

    func authorPosts(id _: String) async throws -> [FeedPost] {
        if failLoad {
            throw FakeError.boom
        }
        return feed
    }

    func pinnedPosts(of _: String) async throws -> [FeedPost] {
        if failPinnedPosts {
            throw FakeError.boom
        }
        return feed.filter(\.isPinned)
    }

    var searchResultsToReturn = SearchResults()
    private(set) var searchQueries: [String] = []
    func search(_ query: String) async throws -> SearchResults {
        searchQueries.append(query)
        if failLoad {
            throw FakeError.boom
        }
        return searchResultsToReturn
    }

    func bookmarkedPosts() async throws -> [FeedPost] {
        feed.filter(\.isBookmarked)
    }

    func likedPosts() async throws -> [FeedPost] {
        feed.filter(\.isLiked)
    }

    func editableSource(of post: FeedPost) async throws -> EditableSource {
        EditableSource(text: String(post.text.characters), spoiler: post.spoilerText ?? "")
    }

    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        editCalls.append((text, spoiler))
        return post
    }

    func report(post _: FeedPost, reason: ReportReason, comment: String) async throws {
        reportPostCalls.append((reason, comment))
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        reportAccountCalls.append(ReportAccountCall(id: id, reason: reason, comment: comment))
    }

    var relationshipsToReturn: [String: AccountRelationship] = [:]
    private(set) var relationshipsRequests: [[String]] = []
    var relationshipsDelay: (() async -> Void)?
    private(set) var relationshipsCompletions = 0

    var setFollowingDelay: (() async -> Void)?
    private(set) var setFollowingCalls: [String] = []

    private(set) var notificationsCalls = 0
    func notifications() async throws -> [FeedNotification] {
        notificationsCalls += 1
        return notificationsToReturn
    }

    private(set) var unreadCountCalls = 0
    func unreadNotificationCount() async throws -> Int {
        unreadCountCalls += 1
        if failUnread {
            throw FakeError.boom
        }
        return unread
    }

    var failMarkRead = false
    /// Awaited after the call is recorded — lets a test suspend the read-mark
    /// mid-flight to stage a tab-switch race deterministically.
    var markReadDelay: (() async -> Void)?
    func markNotificationsRead(upTo latest: FeedNotification?) async throws {
        markedReadCalls.append(latest)
        if let markReadDelay {
            await markReadDelay()
        }
        if failMarkRead {
            throw FakeError.boom
        }
    }

    /// Awaited after the call is recorded — lets a test hold a delete in flight
    /// while it simulates a concurrent poll merge.
    var deleteDelay: (() async -> Void)?
    private(set) var deleteCompletions = 0
    func deletePost(_ post: FeedPost) async throws {
        deletedIDs.append(post.id)
        if let deleteDelay {
            await deleteDelay()
        }
        deleteCompletions += 1
        if failDelete {
            throw FakeError.boom
        }
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

    func likedBy(_: FeedPost) async throws -> [Profile] {
        []
    }

    func repostedBy(_: FeedPost) async throws -> [Profile] {
        []
    }

    private(set) var conversationsCalls = 0

    var messagesDelay: (() async -> Void)?
    private(set) var messagesCalls = 0
    private(set) var messagesCompletions = 0

    var sendMessageDelay: (() async -> Void)?
    private(set) var sentMessages: [String] = []
    private(set) var sendMessageCompletions = 0

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

extension FakeFeedService {
    func relationship(with id: String) async throws -> AccountRelationship {
        if failRelationship {
            throw FakeError.boom
        }
        return relationshipsToReturn[id] ?? AccountRelationship()
    }

    func relationships(with ids: [String]) async throws -> [String: AccountRelationship] {
        relationshipsRequests.append(ids)
        let result = relationshipsToReturn.filter { ids.contains($0.key) }
        if let relationshipsDelay {
            await relationshipsDelay()
        }
        relationshipsCompletions += 1
        if failRelationship {
            throw FakeError.boom
        }
        return result
    }

    func setFollowing(
        _ following: Bool,
        for id: String,
        current: AccountRelationship
    ) async throws -> AccountRelationship {
        setFollowingCalls.append("\(id):\(following)")
        if let setFollowingDelay {
            await setFollowingDelay()
        }
        var copy = current
        copy.isFollowing = following
        return copy
    }

    func setMuted(
        _ muted: Bool,
        for _: String,
        current: AccountRelationship
    ) async throws -> AccountRelationship {
        var copy = current
        copy.isMuting = muted
        return copy
    }

    func setBlocked(
        _ blocked: Bool,
        for _: String,
        current: AccountRelationship
    ) async throws -> AccountRelationship {
        var copy = current
        copy.isBlocking = blocked
        return copy
    }

    func followers(of _: String) async throws -> [Profile] {
        []
    }

    func following(of _: String) async throws -> [Profile] {
        []
    }

    func conversations() async throws -> [Conversation] {
        conversationsCalls += 1
        if failConversations {
            throw FakeError.boom
        }
        return conversationsToReturn
    }

    func messages(in _: String) async throws -> [DirectMessage] {
        messagesCalls += 1
        let result = messagesToReturn
        if let messagesDelay {
            await messagesDelay()
        }
        messagesCompletions += 1
        if failMessages {
            throw FakeError.boom
        }
        return result
    }

    func sendMessage(_ text: String, to _: String) async throws {
        sentMessages.append(text)
        if let sendMessageDelay {
            await sendMessageDelay()
        }
        sendMessageCompletions += 1
        if failSendMessage {
            throw FakeError.boom
        }
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
