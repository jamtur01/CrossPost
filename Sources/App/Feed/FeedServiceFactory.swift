import Foundation
import TootSDK
import ATProtoKit

enum FeedServiceFactory {
    @MainActor
    static func make(for target: PostTarget, store: AccountStore) async throws -> FeedService {
        switch target {
        case .mastodon:
            guard let url = store.mastodonBaseURL else {
                throw PosterFactory.ConfigError.message("Invalid Mastodon instance URL")
            }
            let client = TootClient(instanceURL: url, accessToken: store.mastodonToken)
            try await client.connect()
            if let account = try? await client.verifyCredentials(),
               store.mastodonUsername != account.acct {
                store.mastodonUsername = account.acct   // remember self to skip self-mentions in replies
            }
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
