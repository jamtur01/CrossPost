import Foundation

/// One network's copy of a post CrossPost sent: the first post's link and native
/// ref, and when that copy landed (a retry can land a network later than the other).
struct SentCopy: Codable, Equatable, Sendable {
    let target: PostTarget
    let item: PostedItem
    let date: Date
}

/// A post or thread CrossPost published, with each network's copy of its first post.
struct SentPost: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let postCount: Int
    let copies: [SentCopy]

    func copy(on target: PostTarget) -> SentCopy? {
        copies.first { $0.target == target }
    }

    /// True when both records hold the same published post on some network.
    func sharesCopy(with other: SentPost) -> Bool {
        copies.contains { copy in
            guard let key = copy.item.ref?.postKey else { return false }
            return other.copy(on: copy.target)?.item.ref?.postKey == key
        }
    }

    /// `newer` folded into this record: a retry or continuation of the same send.
    /// Keeps this record's identity and date, takes the newer text and length, and
    /// keeps each existing copy's landing date when the copy itself is unchanged.
    func merging(_ newer: SentPost) -> SentPost {
        let copies = PostTarget.allCases.compactMap { target -> SentCopy? in
            guard let fresh = newer.copy(on: target) else { return copy(on: target) }
            guard let existing = copy(on: target),
                  existing.item.ref?.postKey == fresh.item.ref?.postKey else { return fresh }
            return existing
        }
        return SentPost(id: id, date: date, text: newer.text, postCount: newer.postCount, copies: copies)
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
/// agent can read: `[{"id", "date", "text", "postCount", "copies": [...]}]`.
struct SentHistoryStore: Sendable {
    static let limit = 50
    let url: URL

    /// Saved sends; a missing file is empty, and an unreadable one is logged and
    /// treated as empty rather than blocking the composer.
    func load() -> [SentPost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SentPost].self, from: Data(contentsOf: url))
        } catch {
            Log.history.error("Ignoring unreadable sent history at \(url.path, privacy: .public): \(error)")
            return []
        }
    }

    /// Records `post` and returns the saved history. A send that shares a copy with
    /// an earlier record (a retry finishing the other network, or a thread resumed)
    /// updates that record in place; anything else goes first. Keeps the newest `limit`.
    @discardableResult
    func record(_ post: SentPost) throws -> [SentPost] {
        var history = load()
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
