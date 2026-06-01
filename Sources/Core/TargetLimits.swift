import Foundation

public struct TargetLimits: Sendable {
    public static let blueskyMax = 300
    public static let mastodonFallback = 500

    public let maxGraphemes: [PostTarget: Int]

    public init(mastodonMax: Int = TargetLimits.mastodonFallback) {
        self.maxGraphemes = [
            .mastodon: mastodonMax,
            .bluesky: TargetLimits.blueskyMax,
        ]
    }
}
