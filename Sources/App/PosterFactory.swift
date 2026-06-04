import Foundation
import TootSDK
import ATProtoKit

enum PosterFactory {
    /// Build a connected Mastodon poster and refresh the stored max-character limit.
    @MainActor
    static func makeMastodon(_ store: AccountStore) async throws -> MastodonPoster {
        guard let url = store.mastodonBaseURL else {
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

    /// Build posters for the selected, configured targets. Each target is built
    /// independently so a failure for one (e.g. a stale token) still lets the other
    /// post; the coordinator reports the missing target as a per-target failure.
    @MainActor
    static func makePosters(for targets: [PostTarget], store: AccountStore) async throws -> [Poster] {
        var posters: [Poster] = []
        var errors: [String] = []
        if targets.contains(.mastodon) {
            do { posters.append(try await makeMastodon(store)) }
            catch { errors.append("Mastodon: \(error.userMessage)") }
        }
        if targets.contains(.bluesky) {
            do { posters.append(try await makeBluesky(store)) }
            catch { errors.append("Bluesky: \(error.userMessage)") }
        }
        // Only abort entirely if every selected target failed to connect.
        if posters.isEmpty {
            throw ConfigError.message(errors.joined(separator: "\n"))
        }
        return posters
    }

    enum ConfigError: Error, CustomStringConvertible, LocalizedError {
        case message(String)
        var description: String { switch self { case .message(let m): return m } }
        var errorDescription: String? { description }
    }
}
