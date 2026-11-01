import Foundation

/// One network's copy of a post CrossPost sent: the first post's link and native
/// ref, the account that published it, how many of the thread's posts have landed
/// there, and when that copy landed (a retry can land a network later than the other).
struct SentCopy: Codable, Equatable, Sendable {
    let target: PostTarget
    let item: PostedItem
    let date: Date
    /// The publishing account's key (Mastodon server and username, or Bluesky handle).
    let account: String
    let postCount: Int

    /// The same published post on the same account.
    func isSameCopy(as other: SentCopy) -> Bool {
        guard let key = item.ref?.postKey else { return false }
        return other.target == target && other.account == account && other.item.ref?.postKey == key
    }
}

/// A post or thread CrossPost published, with each network's copy of its first post.
struct SentPost: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    /// Posts in the draft as sent; a copy that stopped partway has fewer.
    let postCount: Int
    let copies: [SentCopy]

    func copy(on target: PostTarget) -> SentCopy? {
        copies.first { $0.target == target }
    }

    /// How many posts every copy published, or nil when the networks differ (a
    /// thread that stopped partway on one of them).
    var commonPublishedCount: Int? {
        let counts = Set(copies.map(\.postCount))
        return counts.count == 1 ? counts.first : nil
    }

    /// True when both records hold the same published post on some network.
    func sharesCopy(with other: SentPost) -> Bool {
        copies.contains { copy in
            other.copy(on: copy.target).map(copy.isSameCopy) ?? false
        }
    }

    /// `newer` folded into this record: a retry or continuation of the same send.
    /// Keeps this record's identity and date, takes the newer text and lengths, and
    /// keeps each existing copy's landing date when the copy itself is unchanged.
    func merging(_ newer: SentPost) -> SentPost {
        let copies = PostTarget.allCases.compactMap { target -> SentCopy? in
            guard let fresh = newer.copy(on: target) else { return copy(on: target) }
            guard let existing = copy(on: target), existing.isSameCopy(as: fresh) else { return fresh }
            return SentCopy(target: target, item: existing.item, date: existing.date,
                            account: existing.account, postCount: fresh.postCount)
        }
        return SentPost(id: id, date: date, text: newer.text, postCount: newer.postCount, copies: copies)
    }

    /// This record limited to the copies published by `accounts` (keyed by network),
    /// or nil when none of them were.
    func limited(to accounts: [PostTarget: String]) -> SentPost? {
        let mine = copies.filter { accounts[$0.target] == $0.account }
        guard !mine.isEmpty else { return nil }
        return SentPost(id: id, date: date, text: text, postCount: postCount, copies: mine)
    }
}

extension NativeRef {
    /// The identity of the post itself, ignoring thread context and content hashes.
    var postKey: String {
        switch self {
        case let .mastodon(statusID): "mastodon:\(statusID)"
        case let .bluesky(uri, _, _, _): uri
        }
    }
}

/// The last sends CrossPost published, newest first, as plain JSON a person or an
/// agent can read: `[{"id", "date", "text", "postCount", "copies": [{"target", "item",
/// "date", "account", "postCount"}]}]`.
struct SentHistoryStore: Sendable {
    /// The history file exists but couldn't be read or decoded, for example one saved
    /// by an earlier version without account names.
    struct Unreadable: Error, CustomStringConvertible {
        let underlying: any Error
        var description: String {
            "\(underlying)"
        }
    }

    static let limit = 50
    let url: URL

    /// Saved sends. A missing file is empty; an unreadable one throws `Unreadable`, so
    /// `record` never replaces history it couldn't read.
    func load() throws -> [SentPost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SentPost].self, from: Data(contentsOf: url))
        } catch {
            throw Unreadable(underlying: error)
        }
    }

    /// Renames an unreadable history file so a new history can start, keeping the old
    /// one beside it, and returns where it went. Nothing is imported from it: its
    /// sends can't be tied to an account.
    func setAside(now: Date = .now) throws -> URL {
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.omitted).timeSeparator(.omitted))
        let kept = url.deletingLastPathComponent().appending(path: "sent-history-unreadable-\(stamp).json")
        try FileManager.default.moveItem(at: url, to: kept)
        return kept
    }

    /// Records `post` and returns the saved history. A send that shares a copy with
    /// an earlier record (a retry finishing the other network, or a thread resumed)
    /// updates that record in place; anything else goes first. Keeps the newest `limit`.
    /// Throws, leaving the file untouched, when the existing history can't be read.
    @discardableResult
    func record(_ post: SentPost) throws -> [SentPost] {
        var history = try load()
        if let index = history.firstIndex(where: { $0.sharesCopy(with: post) }) {
            history[index] = history[index].merging(post)
        } else {
            history.insert(post, at: 0)
        }
        history = Array(history.prefix(Self.limit))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: url, options: .atomic)
        return history
    }
}

/// Where one network's copy of a sent post stands among that account's recent posts.
enum SentCopyStatus: Equatable, Sendable {
    case found(FeedPost)
    /// Missing, but sent moments ago: the network may not list it yet.
    case notYetVisible
    /// Missing and newer than the oldest fetched post, so it was removed.
    case deleted
    /// Missing because it predates everything fetched; its fate is unknown.
    case olderThanRecent

    /// How long a just-sent post may be missing before it counts as deleted.
    static let visibilityGrace: TimeInterval = 120

    /// Matches `copy` against `recent` (the account's own posts) by native ref.
    static func of(_ copy: SentCopy, in recent: [FeedPost], now: Date = .now) -> SentCopyStatus {
        if let key = copy.item.ref?.postKey,
           let post = recent.first(where: { $0.nativeRef.postKey == key }) {
            return .found(post)
        }
        if now.timeIntervalSince(copy.date) < visibilityGrace {
            return .notYetVisible
        }
        // Pinned posts can be far older than the rest, so they don't set the window.
        // An account with no posts left has deleted this one too.
        guard let oldest = recent.filter({ !$0.isPinned }).map(\.date).min() else { return .deleted }
        return copy.date >= oldest ? .deleted : .olderThanRecent
    }
}
