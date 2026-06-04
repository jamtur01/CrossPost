import Foundation

public struct TargetLimits: Sendable {
    public static let blueskyMax = 300
    public static let mastodonFallback = 500
    public static let imageMax = 4

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
