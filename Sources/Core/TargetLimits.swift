import Foundation

public struct TargetLimits: Sendable {
    public static let blueskyMax = 300
    public static let mastodonFallback = 500
    public static let imageMax = 4
    /// Bluesky rejects images over ~1 MB; Mastodon's documented default is 10 MB
    /// (instances report their real cap via `imageSizeLimit`, used when available).
    public static let blueskyImageBytes = 1_000_000
    public static let mastodonImageBytes = 10_000_000

    public let maxGraphemes: [PostTarget: Int]
    public let maxImages: [PostTarget: Int]

    public init(mastodonMax: Int = TargetLimits.mastodonFallback) {
        self.maxGraphemes = [
            .mastodon: mastodonMax,
            .bluesky: TargetLimits.blueskyMax,
        ]
        self.maxImages = [
            .mastodon: TargetLimits.imageMax,
            .bluesky: TargetLimits.imageMax,
        ]
    }
}
