import Foundation
import TootSDK
import ATProtoKit

enum PosterFactory {
    struct MastodonVerification {
        let poster: MastodonPoster
        let maxCharacters: Int
        let username: String
    }

    /// Build a connected Mastodon client, verify its credentials, and write the
    /// server's canonical `acct` back to the store — self-checks (isMine, reply
    /// self-mention skipping) must match the server's spelling. The one shared
    /// verify + write-back path for the poster and feed-service factories, with a
    /// single deliberate error policy: failures throw. connect() has already
    /// succeeded by this point, so a verification failure almost always means a
    /// bad token, and every authenticated call after it would fail with a murkier
    /// error than surfacing the credential problem here.
    @MainActor
    static func makeVerifiedMastodonClient(_ store: AccountStore) async throws -> TootClient {
        guard let url = store.mastodonBaseURL else {
            throw ConfigError.message("Invalid Mastodon instance URL")
        }
        let client = TootClient(instanceURL: url, accessToken: store.mastodonToken)
        try await client.connect()
        let account = try await client.verifyCredentials()
        if store.mastodonUsername != account.acct {
            store.mastodonUsername = account.acct
        }
        return client
    }

    /// Build a connected Mastodon poster and refresh the stored max-character limit.
    @MainActor
    static func makeMastodon(_ store: AccountStore) async throws -> MastodonPoster {
        let client = try await makeVerifiedMastodonClient(store)
        store.mastodonMaxChars = try await client.getInstanceInfoV2().configuration?.posts?.maxCharacters
            ?? TargetLimits.mastodonFallback
        return MastodonPoster(client: client)
    }

    static func makeMastodon(instanceURL: String, token: String) async throws -> MastodonVerification {
        guard let url = AccountStore.normalizedMastodonBaseURL(from: instanceURL) else {
            throw ConfigError.message("Invalid Mastodon instance URL")
        }
        let client = TootClient(instanceURL: url, accessToken: token)
        try await client.connect()
        let account = try await client.verifyCredentials()
        let max = try await client.getInstanceInfoV2().configuration?.posts?.maxCharacters
            ?? TargetLimits.mastodonFallback
        return MastodonVerification(
            poster: MastodonPoster(client: client),
            maxCharacters: max,
            username: account.acct)
    }

    @MainActor
    static func makeBluesky(_ store: AccountStore) async throws -> BlueskyPoster {
        try await makeBluesky(handle: store.blueskyHandle, appPassword: store.blueskyAppPassword)
    }

    static func makeBluesky(handle: String, appPassword: String) async throws -> BlueskyPoster {
        let clients = try await makeBlueskyClients(handle: handle, appPassword: appPassword)
        return BlueskyPoster(bluesky: clients.bluesky, handle: handle.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Authenticate Bluesky and return both the kit (for reads) and the Bluesky client (for writes).
    @MainActor
    static func makeBlueskyClients(_ store: AccountStore) async throws -> (kit: ATProtoKit, bluesky: ATProtoBluesky) {
        try await makeBlueskyClients(handle: store.blueskyHandle, appPassword: store.blueskyAppPassword)
    }

    static func makeBlueskyClients(handle: String, appPassword: String) async throws -> (kit: ATProtoKit, bluesky: ATProtoBluesky) {
        let config = ATProtocolConfiguration()
        try await config.authenticate(
            with: handle.trimmingCharacters(in: .whitespacesAndNewlines),
            password: appPassword)
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
        if targets.contains(.mastodon) {
            do { posters.append(try await makeMastodon(store)) }
            catch { posters.append(FailedPoster(target: .mastodon, message: error.userMessage)) }
        }
        if targets.contains(.bluesky) {
            do { posters.append(try await makeBluesky(store)) }
            catch { posters.append(FailedPoster(target: .bluesky, message: error.userMessage)) }
        }
        return posters
    }

    private struct FailedPoster: Poster {
        let target: PostTarget
        let message: String

        func post(thread: [DraftPost], continuingFrom ref: NativeRef?) async throws -> [PostedItem] {
            throw ConfigError.message(message)
        }
    }

    enum ConfigError: Error, CustomStringConvertible, LocalizedError {
        case message(String)
        var description: String { switch self { case .message(let m): return m } }
        var errorDescription: String? { description }
    }
}
