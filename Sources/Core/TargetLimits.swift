import Foundation

struct TargetLimits: Sendable {
    static let blueskyMax = 300
    /// Bluesky's lexicon caps post text at 3000 UTF-8 bytes in addition to 300 graphemes.
    static let blueskyMaxBytes = 3_000
    static let mastodonFallback = 500
    static let imageMax = 4
    /// Bluesky rejects images over ~1 MB; Mastodon's documented default is 10 MB
    /// (instances report their real cap via `imageSizeLimit`, used when available).
    static let blueskyImageBytes = 1_000_000
    static let mastodonImageBytes = 10_000_000

    let maxGraphemes: [PostTarget: Int]
    let maxBytes: [PostTarget: Int]
    let maxImages: [PostTarget: Int]

    init(mastodonMax: Int = TargetLimits.mastodonFallback) {
        self.maxGraphemes = [
            .mastodon: mastodonMax,
            .bluesky: TargetLimits.blueskyMax,
        ]
        self.maxBytes = [
            .bluesky: TargetLimits.blueskyMaxBytes,
        ]
        self.maxImages = [
            .mastodon: TargetLimits.imageMax,
            .bluesky: TargetLimits.imageMax,
        ]
    }
}
