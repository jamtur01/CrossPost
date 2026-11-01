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
    /// Why the history file couldn't be read or saved (the file is left as it was),
    /// or where an unreadable file was kept when a new history was started.
    enum Problem: Equatable {
        case unreadable
        case unsaved(String)
        /// Starting a new history failed; the unreadable file is still in place.
        case resetFailed(String)
        case setAside(URL)

        /// Whether the unreadable file is still in the way, so starting over is offered.
        var offersReset: Bool {
            switch self {
            case .unreadable, .resetFailed: true
            case .unsaved, .setAside: false
            }
        }
    }

    /// Waits out a follow-up refresh's delay; throws when the follow-up is cancelled.
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// How long after a send lands its counts are re-read on their own: soon, when the
    /// network usually lists it, and again just after the visibility grace ends.
    static let followUpOffsets: [TimeInterval] = [15, SentCopyStatus.visibilityGrace + 1]

    private(set) var problem: Problem?
    @ObservationIgnored private var fetches: [PostTarget: Task<Void, Never>] = [:]
    @ObservationIgnored private var followUp: Task<Void, Never>?
    private let store: SentHistoryStore
    private let account: @MainActor (PostTarget) -> String?
    private let makeService: MentionDirectory.MakeService
    private let now: @MainActor () -> Date
    private let sleep: Sleep

    /// `account` gives a network's signed-in account key, or nil when it has none.
    /// `now` and `sleep` time the follow-up refreshes after a send.
    init(store: SentHistoryStore,
         account: @escaping @MainActor (PostTarget) -> String?,
         makeService: @escaping MentionDirectory.MakeService,
         now: @escaping @MainActor () -> Date = { .now },
         sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.account = account
        self.makeService = makeService
        self.now = now
        self.sleep = sleep
        readAccounts()
        do {
            posts = try store.load()
        } catch {
            Log.history.error("Couldn't read sent history at \(store.url.path, privacy: .public): \(error)")
            problem = .unreadable
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
        followUp?.cancel()
    }

    /// Saves a send. A failure leaves the file as it was and is shown in Recent Posts.
    func record(_ post: SentPost) {
        do {
            posts = try store.record(post)
            problem = nil
            scheduleFollowUp()
        } catch {
            let path = store.url.path
            Log.history.error("Couldn't save sent history at \(path, privacy: .public): \(error)")
            problem = error is SentHistoryStore.Unreadable ? .unreadable : .unsaved(error.userMessage)
        }
    }

    /// Keeps an unreadable history file under a new name and starts an empty history,
    /// so new sends are recorded again. The old file's sends aren't imported.
    func startNewHistory() {
        do {
            let kept = try store.setAside()
            Log.history.info("Kept unreadable sent history as \(kept.path, privacy: .public)")
            posts = []
            problem = .setAside(kept)
            refresh()
        } catch {
            let path = store.url.path
            Log.history.error("Couldn't set aside sent history at \(path, privacy: .public): \(error)")
            problem = .resetFailed(error.userMessage)
        }
    }

    /// Re-reads which accounts are signed in and each one's recent posts. Copies from
    /// other accounts, and networks without an account, are omitted rather than
    /// matched against the wrong account's posts.
    /// While the newest send is within its visibility grace, also schedules the next
    /// follow-up refresh, replacing any pending one.
    func refresh() {
        fetches.values.forEach { $0.cancel() }
        fetches = [:]
        readAccounts()
        scheduleFollowUp()
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

    /// Re-reads counts at the next follow-up offset after the newest visible send, so
    /// "Just posted" resolves without a manual refresh. A refresh reschedules it, and
    /// nothing is scheduled once the grace has passed.
    private func scheduleFollowUp() {
        followUp?.cancel()
        followUp = nil
        let current = now()
        guard let landed = visiblePosts.flatMap(\.copies).map(\.date).max(),
              let due = Self.followUpOffsets.map({ landed.addingTimeInterval($0) }).first(where: { $0 > current })
        else { return }
        let sleep = sleep
        followUp = Task { [weak self] in
            do {
                try await sleep(.seconds(due.timeIntervalSince(current)))
            } catch {
                return // Replaced by a newer refresh, or the model went away.
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
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
