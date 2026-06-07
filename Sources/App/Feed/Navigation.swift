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

/// A destination within a feed column's in-place navigation stack.
enum FeedRoute: Identifiable {
    case thread(FeedPost)
    case profile(ProfileRef)
    case profileList(ProfileListRef)

    var id: String {
        switch self {
        case .thread(let post): return "thread:\(post.id)"
        case .profile(let ref): return "profile:\(ref.id):\(ref.isMe)"
        case .profileList(let ref): return "list:\(ref.id)"
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
        mutate(post, optimistic: { $0.isLiked.toggle() }) { [panel] in
            try await panel.serviceSetLiked($0.isLiked, on: $0)
        }
    }

    func toggleRepost(_ post: FeedPost) {
        mutate(post, optimistic: { $0.isReposted.toggle() }) { [panel] in
            try await panel.serviceSetReposted($0.isReposted, on: $0)
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
            }
        }
    }
}
