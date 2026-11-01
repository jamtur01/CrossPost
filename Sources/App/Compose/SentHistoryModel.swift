import Foundation

/// The composer's "Recent Posts": what CrossPost sent, and how each network's copy
/// is doing, read from that account's own recent posts on demand (never polled).
@MainActor
@Observable
final class SentHistoryModel {
    /// One network's recent posts, as last fetched.
    enum RecentPosts: Equatable {
        case loading
        case loaded([FeedPost])
        case failed(String)
    }

    /// What a row shows for one network's copy.
    enum CopyState: Equatable {
        case loading
        case unreachable(String)
        case status(SentCopyStatus)
    }

    private(set) var posts: [SentPost]
    private(set) var recent: [PostTarget: RecentPosts] = [:]
    @ObservationIgnored private var fetches: [PostTarget: Task<Void, Never>] = [:]
    private let store: SentHistoryStore
    private let isConfigured: @MainActor (PostTarget) -> Bool
    private let makeService: MentionDirectory.MakeService

    init(store: SentHistoryStore,
         isConfigured: @escaping @MainActor (PostTarget) -> Bool,
         makeService: @escaping MentionDirectory.MakeService) {
        self.store = store
        self.isConfigured = isConfigured
        self.makeService = makeService
        posts = store.load()
    }

    isolated deinit {
        fetches.values.forEach { $0.cancel() }
    }

    /// Saves a send. A failed write is logged, never surfaced: the post itself landed.
    func record(_ post: SentPost) {
        do {
            posts = try store.record(post)
        } catch {
            let path = store.url.path
            Log.history.error("Couldn't save sent history at \(path, privacy: .public): \(error)")
        }
    }

    /// Re-reads each configured network's recent posts. Networks without an account
    /// are dropped, so their copies are omitted rather than shown as failures.
    func refresh() {
        fetches.values.forEach { $0.cancel() }
        fetches = [:]
        let targets = PostTarget.allCases.filter(isConfigured)
        recent = Dictionary(uniqueKeysWithValues: targets.map { ($0, .loading) })
        guard !posts.isEmpty else { return }
        for target in targets {
            fetches[target] = Task { [weak self] in
                guard let self else { return }
                let result = await fetchRecentPosts(on: target)
                guard !Task.isCancelled else { return }
                recent[target] = result
            }
        }
    }

    /// Nil when `target` has no account configured, so the row omits that network.
    func state(of copy: SentCopy, now: Date = .now) -> CopyState? {
        switch recent[copy.target] {
        case nil: nil
        case .loading: .loading
        case let .failed(message): .unreachable(message)
        case let .loaded(posts): .status(SentCopyStatus.of(copy, in: posts, now: now))
        }
    }

    private func fetchRecentPosts(on target: PostTarget) async -> RecentPosts {
        do {
            let service = try await makeService(target)
            let profile = try await service.myProfile()
            return try await .loaded(service.authorPosts(id: profile.id))
        } catch {
            Log.history.error("Recent posts failed on \(target.rawValue, privacy: .public): \(error)")
            return .failed(error.userMessage)
        }
    }
}

extension SentHistoryStore {
    static let application: SentHistoryStore = {
        // Hosted tests launch the app UI too; it must never touch the real history.
        if ProcessInfo.processInfo.isRunningTests {
            return SentHistoryStore(url: URL.temporaryDirectory
                .appending(path: "CrossPost-tests-\(UUID())/sent-history.json"))
        }
        return SentHistoryStore(url: URL.applicationSupportDirectory
            .appending(path: "CrossPost/sent-history.json"))
    }()
}
