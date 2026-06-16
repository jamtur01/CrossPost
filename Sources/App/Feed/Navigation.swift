import SwiftUI

/// A lightweight reference to a profile, enough to push a route and show a
/// placeholder header while the full profile loads.
struct ProfileRef: Identifiable, Equatable {
    let id: String          // authorID (Mastodon account id / Bluesky handle)
    let handle: String
    let name: String
    let avatar: URL?
    var isMe: Bool = false
}

/// A reference to a list of accounts to display: followers, following, or the
/// accounts that liked / reposted a post.
struct ProfileListRef: Identifiable {
    enum Kind: String { case followers, following, likedBy, repostedBy }
    let kind: Kind
    let accountID: String
    let post: FeedPost?

    init(kind: Kind, accountID: String = "", post: FeedPost? = nil) {
        self.kind = kind
        self.accountID = accountID
        self.post = post
    }

    var id: String { "\(kind.rawValue):\(post?.id ?? accountID)" }
    var title: String {
        switch kind {
        case .followers: return "Followers"
        case .following: return "Following"
        case .likedBy: return "Liked by"
        case .repostedBy: return "Reposted by"
        }
    }
}

/// One of the signed-in user's saved-post collections.
enum SavedKind: String, Identifiable {
    case bookmarks, likes
    var id: String { rawValue }
    var title: String { self == .bookmarks ? "Bookmarks" : "Likes" }
    var icon: String { self == .bookmarks ? "bookmark" : "heart" }
}

/// A destination within a feed column's in-place navigation stack.
enum FeedRoute: Identifiable {
    case thread(FeedPost)
    case profile(ProfileRef)
    case profileList(ProfileListRef)
    case conversation(Conversation)
    case saved(SavedKind)

    var id: String {
        switch self {
        case .thread(let post): return "thread:\(post.id)"
        case .profile(let ref): return "profile:\(ref.id):\(ref.isMe)"
        case .profileList(let ref): return "list:\(ref.id)"
        case .conversation(let convo): return "convo:\(convo.id)"
        case .saved(let kind): return "saved:\(kind.rawValue)"
        }
    }
}

extension FeedPost {
    func profileRef() -> ProfileRef {
        ProfileRef(id: authorID, handle: authorHandle, name: authorName, avatar: avatarURL)
    }
}

/// Holds a list of posts (a thread or a profile's feed) with optimistic
/// like/repost backed by the panel's service.
@MainActor
@Observable
final class PostList {
    var posts: [FeedPost] = []
    private let panel: FeedPanelModel
    private var mutating: Set<String> = []

    init(panel: FeedPanelModel) { self.panel = panel }

    func toggleLike(_ post: FeedPost) {
        mutate(post, optimistic: {
            $0.isLiked.toggle()
            $0.likeCount = max(0, $0.likeCount + ($0.isLiked ? 1 : -1))
        }) { [panel] in
            try await panel.serviceSetLiked($0.isLiked, on: $0)
        }
    }

    func toggleRepost(_ post: FeedPost) {
        mutate(post, optimistic: {
            $0.isReposted.toggle()
            $0.repostCount = max(0, $0.repostCount + ($0.isReposted ? 1 : -1))
        }) { [panel] in
            try await panel.serviceSetReposted($0.isReposted, on: $0)
        }
    }

    func setBookmarked(_ bookmarked: Bool, _ post: FeedPost) {
        mutate(post, optimistic: { $0.isBookmarked = bookmarked }) { [panel] in
            try await panel.serviceSetBookmarked(bookmarked, on: $0)
        }
    }

    func setPinned(_ pinned: Bool, _ post: FeedPost) {
        mutate(post, optimistic: { $0.isPinned = pinned }) { [panel] in
            try await panel.serviceSetPinned(pinned, on: $0)
        }
    }

    /// Optimistically remove a row, deleting it on the server and re-inserting it
    /// at its original position (with an error banner) if the delete fails.
    func delete(_ post: FeedPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let removed = posts.remove(at: index)
        Task { [panel] in
            do { try await panel.serviceDeletePost(post) }
            catch {
                if !posts.contains(where: { $0.id == post.id }) {
                    posts.insert(removed, at: min(index, posts.count))
                }
                panel.reportActionError(error.userMessage)
            }
        }
    }

    private func mutate(_ post: FeedPost,
                        optimistic: (inout FeedPost) -> Void,
                        action: @escaping (FeedPost) async throws -> FeedPost) {
        guard !mutating.contains(post.id),
              let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        mutating.insert(post.id)
        let original = posts[index]
        var optimisticPost = original
        optimistic(&optimisticPost)
        posts[index] = optimisticPost
        Task {
            defer { mutating.remove(post.id) }
            do {
                let updated = try await action(optimisticPost)
                if let i = posts.firstIndex(where: { $0.id == post.id }), posts[i] == optimisticPost {
                    posts[i] = updated
                }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }), posts[i] == optimisticPost {
                    posts[i] = original
                }
                panel.reportActionError(error.userMessage)
            }
        }
    }
}
