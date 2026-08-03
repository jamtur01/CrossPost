import SwiftUI

/// A lightweight reference to a profile, enough to push a route and show a
/// placeholder header while the full profile loads.
struct ProfileRef: Identifiable, Equatable {
    let id: String // authorID (Mastodon account id / Bluesky handle)
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

    var id: String {
        "\(kind.rawValue):\(post?.id ?? accountID)"
    }

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
    var id: String {
        rawValue
    }

    var title: String {
        self == .bookmarks ? "Bookmarks" : "Likes"
    }

    var icon: String {
        self == .bookmarks ? "bookmark" : "heart"
    }
}

/// A destination within a feed column's in-place navigation stack.
enum FeedRoute: Identifiable {
    case thread(FeedPost)
    case profile(ProfileRef)
    case profileList(ProfileListRef)
    case conversation(Conversation)
    case saved(SavedKind)
    case search

    var id: String {
        switch self {
        case let .thread(post): return "thread:\(post.id)"
        case let .profile(ref): return "profile:\(ref.id):\(ref.isMe)"
        case let .profileList(ref): return "list:\(ref.id)"
        case let .conversation(convo): return "convo:\(convo.id)"
        case let .saved(kind): return "saved:\(kind.rawValue)"
        case .search: return "search"
        }
    }
}

extension FeedPost {
    func profileRef() -> ProfileRef {
        ProfileRef(id: authorID, handle: authorHandle, name: authorName, avatar: avatarURL)
    }
}

extension Profile {
    func profileRef() -> ProfileRef {
        ProfileRef(id: id, handle: handle, name: name, avatar: avatarURL)
    }
}

/// Holds a list of posts (a thread or a profile's feed). Optimistic like/repost/
/// bookmark/pin/delete come from the shared `OptimisticPostHost` engine; this type
/// only supplies the remote calls (routed through the panel's service) and the
/// error sink.
@MainActor
@Observable
final class PostList: OptimisticPostHost {
    var posts: [FeedPost] = []
    var inFlight: Set<String> = []
    @ObservationIgnored var mutationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var mutationGeneration: UInt = 0
    private let panel: FeedPanelModel

    init(panel: FeedPanelModel) {
        self.panel = panel
    }

    func reportError(_ message: String) {
        panel.reportError(message)
    }

    var remoteMutationGeneration: UInt {
        panel.mutationGeneration
    }

    func remoteSetLiked(
        _ liked: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await panel.remoteSetLiked(liked, on: post, generation: generation)
    }

    func remoteSetReposted(
        _ reposted: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await panel.remoteSetReposted(reposted, on: post, generation: generation)
    }

    func remoteSetBookmarked(
        _ bookmarked: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await panel.remoteSetBookmarked(bookmarked, on: post, generation: generation)
    }

    func remoteSetPinned(
        _ pinned: Bool,
        on post: FeedPost,
        generation: UInt
    ) async throws -> FeedPost {
        try await panel.remoteSetPinned(pinned, on: post, generation: generation)
    }

    func remoteDelete(_ post: FeedPost, generation: UInt) async throws {
        try await panel.remoteDelete(post, generation: generation)
    }
}
