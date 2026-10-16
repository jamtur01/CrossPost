import Foundation

/// Account pairings made by hand, kept as plain JSON so a person or an agent can
/// edit them: `[{"mastodonAcct": "...", "blueskyHandle": "..."}]`.
struct MentionPairStore: Sendable {
    let url: URL

    /// Saved pairs; a missing file is empty, and an unreadable one is logged
    /// and treated as empty rather than blocking mention search.
    func load() -> [MentionPair] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([MentionPair].self, from: Data(contentsOf: url))
        } catch {
            Log.mentions.error("Ignoring unreadable mention pairs at \(url.path, privacy: .public): \(error)")
            return []
        }
    }

    /// Saves `pair`, replacing any existing pairing for either of its accounts.
    func save(_ pair: MentionPair) throws {
        var pairs = load().filter {
            !$0.matches(mastodonAcct: pair.mastodonAcct) && !$0.matches(blueskyHandle: pair.blueskyHandle)
        }
        pairs.append(pair)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pairs).write(to: url, options: .atomic)
    }
}
