import Foundation

struct TargetLimits: Sendable {
    static let blueskyMax = 300
    /// Bluesky's lexicon caps post text at 3000 UTF-8 bytes in addition to 300 graphemes.
    static let blueskyMaxBytes = 3_000
    static let mastodonFallback = 500
    static let imageMax = 4
    /// Bluesky's images lexicon caps blobs at 2 MB (raised from 1 MB in April 2026);
    /// Mastodon's documented default is 10 MB (instances report their real cap via
    /// `imageSizeLimit`, used when available).
    static let blueskyImageBytes = 2_000_000
    static let mastodonImageBytes = 10_000_000
    /// Image alt-text caps: Mastodon enforces 1,500 characters server-side; Bluesky's
    /// lexicon sets no limit, so we follow the official app's de-facto 2,000.
    static let mastodonAltMax = 1_500
    static let blueskyAltMax = 2_000

    let maxGraphemes: [PostTarget: Int]
    let maxBytes: [PostTarget: Int]
    let maxImages: [PostTarget: Int]
    let maxAltText: [PostTarget: Int]

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
        self.maxAltText = [
            .mastodon: TargetLimits.mastodonAltMax,
            .bluesky: TargetLimits.blueskyAltMax,
        ]
    }

    /// The single place the per-post image cap is computed. Pre-flight validation
    /// and the upload paths all funnel through here so the cap and its error text
    /// can't drift apart between layers.
    func imageCountViolation(count: Int, for target: PostTarget) -> MediaValidationError? {
        guard let limit = maxImages[target], count > limit else { return nil }
        return .tooManyImages(target: target, count: count, limit: limit)
    }

    /// Throwing form of `imageCountViolation` for the upload paths.
    func checkImageCount(_ count: Int, for target: PostTarget) throws {
        if let violation = imageCountViolation(count: count, for: target) {
            throw violation
        }
    }
}
