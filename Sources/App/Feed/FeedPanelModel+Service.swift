import Foundation

@MainActor
extension FeedPanelModel {
    /// Fetch the surrounding thread (ancestors + replies) for the detail view.
    /// These detail-view fetches propagate errors so the views can show a real
    /// error state with retry, rather than an empty pane that hides a failure.
    func thread(of post: FeedPost) async throws -> PostThread {
        try await resolveService().thread(of: post)
    }

    func profile(id: String) async throws -> Profile {
        try await resolveService().profile(id: id)
    }

    func myProfile() async throws -> Profile {
        try await resolveService().myProfile()
    }

    func authorPosts(id: String) async throws -> [FeedPost] {
        try await resolveService().authorPosts(id: id)
    }

    func pinnedPosts(id: String) async throws -> [FeedPost] {
        try await resolveService().pinnedPosts(of: id)
    }

    func search(_ query: String) async throws -> SearchResults {
        try await resolveService().search(query)
    }

    func bookmarkedPosts() async throws -> [FeedPost] {
        try await resolveService().bookmarkedPosts()
    }

    func likedPosts() async throws -> [FeedPost] {
        try await resolveService().likedPosts()
    }

    func editableSource(of post: FeedPost) async throws -> EditableSource {
        try await resolveService().editableSource(of: post)
    }

    func edit(post: FeedPost, text: String, spoiler: String) async throws -> FeedPost {
        let updated = try await resolveService().edit(post: post, text: text, spoiler: spoiler)
        // Update this panel's timeline row immediately; also refresh so the rest of
        // the platform's surfaces (and counts) catch up.
        updatePost(post.id) { $0 = updated }
        NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                        userInfo: [crossPostTargetsKey: Set([post.target])])
        return updated
    }

    func quote(post: FeedPost, text: String,
               visibility: PostVisibility) async throws -> PostedItem {
        let item = try await resolveService().quote(post: post, text: text, visibility: visibility)
        // Refresh this platform's feed so the new quote shows up.
        NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                        userInfo: [crossPostTargetsKey: Set([post.target])])
        return item
    }

    func report(post: FeedPost, reason: ReportReason, comment: String) async throws {
        try await resolveService().report(post: post, reason: reason, comment: comment)
    }

    func report(accountID id: String, reason: ReportReason, comment: String) async throws {
        try await resolveService().report(accountID: id, reason: reason, comment: comment)
    }

    func relationship(with id: String) async throws -> AccountRelationship {
        try await resolveService().relationship(with: id)
    }
}
