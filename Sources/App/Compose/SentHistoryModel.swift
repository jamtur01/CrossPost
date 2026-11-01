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

    /// Every saved send, across all accounts.
    private(set) var posts: [SentPost] = []
    /// The signed-in account per network, as of the last refresh.
    private(set) var accounts: [PostTarget: String] = [:]
    private(set) var recent: [PostTarget: RecentPosts] = [:]
    /// Why the history file couldn't be read or saved; the file is left as it was.
    private(set) var problem: String?
    @ObservationIgnored private var fetches: [PostTarget: Task<Void, Never>] = [:]
    private let store: SentHistoryStore
    private let account: @MainActor (PostTarget) -> String?
    private let makeService: MentionDirectory.MakeService

    /// `account` gives a network's signed-in account key, or nil when it has none.
    init(store: SentHistoryStore,
         account: @escaping @MainActor (PostTarget) -> String?,
         makeService: @escaping MentionDirectory.MakeService) {
        self.store = store
        self.account = account
        self.makeService = makeService
        readAccounts()
        do {
            posts = try store.load()
        } catch {
            Log.history.error("Couldn't read sent history at \(store.url.path, privacy: .public): \(error)")
            problem = "Your post history couldn't be read, so new posts aren't being added to it. "
                + "The file is unchanged."
        }
    }

    /// Sends published by the signed-in accounts, showing only those accounts' copies.
    var visiblePosts: [SentPost] {
        posts.compactMap { $0.limited(to: accounts) }
    }

    /// The history file, for showing in Finder when it can't be read or saved.
    var fileURL: URL {
        store.url
    }

    isolated deinit {
        fetches.values.forEach { $0.cancel() }
    }

    /// Saves a send. A failure leaves the file as it was and is shown in Recent Posts.
    func record(_ post: SentPost) {
        do {
            posts = try store.record(post)
            problem = nil
        } catch {
            let path = store.url.path
            Log.history.error("Couldn't save sent history at \(path, privacy: .public): \(error)")
            problem = "This post couldn't be added to your post history (\(error.userMessage)). "
                + "The file is unchanged."
        }
    }

    /// Re-reads which accounts are signed in and each one's recent posts. Copies from
    /// other accounts, and networks without an account, are omitted rather than
    /// matched against the wrong account's posts.
    func refresh() {
        fetches.values.forEach { $0.cancel() }
        fetches = [:]
        readAccounts()
        let targets = PostTarget.allCases.filter { accounts[$0] != nil }
        recent = Dictionary(uniqueKeysWithValues: targets.map { ($0, .loading) })
        guard !visiblePosts.isEmpty else { return }
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

    private func readAccounts() {
        accounts = Dictionary(uniqueKeysWithValues: PostTarget.allCases.compactMap { target in
            account(target).map { (target, $0) }
        })
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
