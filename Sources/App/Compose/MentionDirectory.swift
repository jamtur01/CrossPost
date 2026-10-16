import Foundation

/// Searches each network for mention candidates and merges them into people.
/// Feed services are created on first use and dropped when credentials change.
@MainActor
final class MentionDirectory {
    typealias MakeService = @MainActor (PostTarget) async throws -> FeedService

    struct Results: Equatable, Sendable {
        var people: [MentionPerson]
        var failed: [PostTarget]
    }

    let pairStore: MentionPairStore
    private let makeService: MakeService
    private var services: [PostTarget: FeedService] = [:]
    private var credentialsObserver: NSObjectProtocol?

    init(pairStore: MentionPairStore, makeService: @escaping MakeService) {
        self.pairStore = pairStore
        self.makeService = makeService
        credentialsObserver = NotificationCenter.default.addObserver(
            forName: .crossPostCredentialsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.services = [:] }
        }
    }

    deinit {
        credentialsObserver.map(NotificationCenter.default.removeObserver)
    }

    func search(_ query: String, on targets: [PostTarget]) async -> Results {
        async let mastodon = candidates(query, on: .mastodon, if: targets.contains(.mastodon))
        async let bluesky = candidates(query, on: .bluesky, if: targets.contains(.bluesky))
        let (mastodonResult, blueskyResult) = await (mastodon, bluesky)
        let people = MentionMerger.merge(mastodon: mastodonResult ?? [], bluesky: blueskyResult ?? [],
                                         pairs: pairStore.load())
        let failed = [(PostTarget.mastodon, mastodonResult), (.bluesky, blueskyResult)]
            .filter { targets.contains($0.0) && $0.1 == nil }
            .map(\.0)
        return Results(people: Array(people.prefix(8)), failed: failed)
    }

    /// Candidates from one network: empty when it isn't searched, nil on failure.
    private func candidates(_ query: String, on target: PostTarget,
                            if enabled: Bool) async -> [MentionCandidate]? {
        guard enabled else { return [] }
        do {
            return try await service(for: target).mentionCandidates(matching: query)
        } catch {
            Log.mentions.error("Mention search failed on \(target.rawValue, privacy: .public): \(error)")
            return nil
        }
    }

    // ponytail: two concurrent first searches may each build a service; the
    // second simply replaces the first in the cache.
    private func service(for target: PostTarget) async throws -> FeedService {
        if let service = services[target] {
            return service
        }
        let service = try await makeService(target)
        services[target] = service
        return service
    }
}
