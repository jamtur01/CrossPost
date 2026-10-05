import Foundation

/// Session-owned notification previews, including short-lived misses for deleted posts.
actor NotificationPostCache {
    struct Snapshot: Sendable {
        var posts: [String: FeedPost] = [:]
        var missing: [String] = []
        let generation: UInt
    }

    private struct Entry {
        let post: FeedPost?
        let date: Date
    }

    private var entries: [String: Entry] = [:]
    private var generation: UInt = 0

    func snapshot(for uris: Set<String>, now: Date = Date()) -> Snapshot {
        var result = Snapshot(generation: generation)
        for uri in uris {
            result.posts[uri] = entries[uri]?.post
            if let entry = entries[uri], now.timeIntervalSince(entry.date) < 60 {
                continue
            } else {
                result.missing.append(uri)
            }
        }
        return result
    }

    func insert(_ posts: [String: FeedPost], requested: [String], generation: UInt, now: Date = Date()) {
        guard generation == self.generation else { return }
        for uri in requested {
            entries[uri] = Entry(post: posts[uri], date: now)
        }
        let oldest = entries.keys.sorted {
            let left = entries[$0]?.date ?? .distantPast
            let right = entries[$1]?.date ?? .distantPast
            return left == right ? $0 < $1 : left < right
        }
        for uri in oldest.prefix(max(0, entries.count - 200)) {
            entries[uri] = nil
        }
    }

    func invalidate(_ uri: String) {
        generation &+= 1
        entries[uri] = nil
    }
}
