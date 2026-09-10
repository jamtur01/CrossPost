import ATProtoKit
import Foundation
import TootSDK

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
            let handle = store.blueskyHandle
            let password = store.blueskyAppPassword
            let clients = try await PosterFactory.makeBlueskyClients(store)
            // Store the server's canonical handle so self-checks (isMine, reply
            // self-mention, "my profile") match regardless of how the user typed it.
            guard let session = try await clients.kit.getUserSession() else {
                throw PosterFactory.ConfigError
                    .message("Bluesky session is unavailable. Verify the account in Settings.")
            }
            guard store.blueskyHandle == handle, store.blueskyAppPassword == password else {
                throw PosterFactory.ConfigError.message("Bluesky account changed while connecting. Try again.")
            }
            if store.blueskyHandle != session.handle {
                store.blueskyHandle = session.handle
            }
            store.rememberOwnAccount(session.sessionDID, for: .bluesky)
            return BlueskyFeedService(kit: clients.kit, bluesky: clients.bluesky, handle: store.blueskyHandle)
        }
    }
}
