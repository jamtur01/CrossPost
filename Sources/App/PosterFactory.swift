import Foundation
import TootSDK
import ATProtoKit

enum PosterFactory {
    /// Build a connected Mastodon poster and refresh the stored max-character limit.
    @MainActor
    static func makeMastodon(_ store: AccountStore) async throws -> MastodonPoster {
        guard let url = URL(string: store.mastodonInstanceURL) else {
            throw ConfigError.message("Invalid Mastodon instance URL")
        }
        let client = TootClient(instanceURL: url, accessToken: store.mastodonToken)
        try await client.connect()
        if let max = try await client.getInstanceInfoV2().configuration?.posts?.maxCharacters {
            store.mastodonMaxChars = max
        }
        return MastodonPoster(client: client)
    }

    @MainActor
    static func makeBluesky(_ store: AccountStore) async throws -> BlueskyPoster {
        let clients = try await makeBlueskyClients(store)
        return BlueskyPoster(bluesky: clients.bluesky, handle: store.blueskyHandle)
    }

    /// Authenticate Bluesky and return both the kit (for reads) and the Bluesky client (for writes).
    @MainActor
    static func makeBlueskyClients(_ store: AccountStore) async throws -> (kit: ATProtoKit, bluesky: ATProtoBluesky) {
        let config = ATProtocolConfiguration()
        try await config.authenticate(with: store.blueskyHandle, password: store.blueskyAppPassword)
        let kit = await ATProtoKit(sessionConfiguration: config)
        let bluesky = ATProtoBluesky(atProtoKitInstance: kit)
        return (kit, bluesky)
    }

    /// Build posters for the selected, configured targets.
    @MainActor
    static func makePosters(for targets: [PostTarget], store: AccountStore) async throws -> [Poster] {
        var posters: [Poster] = []
        if targets.contains(.mastodon) { posters.append(try await makeMastodon(store)) }
        if targets.contains(.bluesky) { posters.append(try await makeBluesky(store)) }
        return posters
    }

    enum ConfigError: Error, CustomStringConvertible {
        case message(String)
        var description: String { switch self { case .message(let m): return m } }
    }
}
