import Foundation
import TootSDK
import ATProtoKit

enum FeedServiceFactory {
    @MainActor
    static func make(for target: PostTarget, store: AccountStore) async throws -> FeedService {
        switch target {
        case .mastodon:
            // Shared verify + username write-back; verification failures now
            // propagate instead of being swallowed (see makeVerifiedMastodonClient).
            let client = try await PosterFactory.makeVerifiedMastodonClient(store)
            return MastodonFeedService(client: client)
        case .bluesky:
            let clients = try await PosterFactory.makeBlueskyClients(store)
            // Store the server's canonical handle so self-checks (isMine, reply
            // self-mention, "my profile") match regardless of how the user typed it.
            if let profile = try? await clients.kit.getProfile(for: store.blueskyHandle),
               store.blueskyHandle.lowercased() != profile.actorHandle.lowercased() {
                store.blueskyHandle = profile.actorHandle
            }
            return BlueskyFeedService(kit: clients.kit, bluesky: clients.bluesky, handle: store.blueskyHandle)
        }
    }
}
