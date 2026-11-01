import Observation

/// A post, or a quoted post, whose content warning and sensitive media the reader
/// can reveal.
protocol Revealable {
    /// Identifies the underlying post. A quote's key matches the quoted post's own,
    /// so opening it in either place opens it in both.
    var revealKey: String { get }
    var spoilerText: String? { get }
    var isSensitive: Bool { get }
}

extension Revealable {
    /// The content warning shown in place of the post, if it has one: Mastodon's
    /// own, or one Bluesky labels call for.
    var contentWarning: String? {
        guard let spoilerText, !spoilerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return spoilerText
    }
}

extension FeedPost: Revealable {
    var revealKey: String {
        nativeRef.postKey
    }
}

extension QuotedPost: Revealable {
    var revealKey: String {
        id
    }
}

/// Which content warnings and sensitive media the user has opened this session.
/// Owned by the panel so it outlives recycled timeline rows and pushed routes, and
/// keyed by the underlying post so a boost row, its thread, and a quote of it share
/// the choice. Never persisted: every launch starts with warnings closed and media
/// covered.
@MainActor
@Observable
final class PostReveals {
    private var openedWarnings: Set<String> = []
    private var shownMedia: Set<String> = []

    /// Whether the post's body, media, link card, and quote are visible: always
    /// for posts without a content warning, otherwise once the user opens it.
    func showsContent(of post: some Revealable) -> Bool {
        post.contentWarning == nil || openedWarnings.contains(post.revealKey)
    }

    /// Whether the post's media is unblurred. Opening a content warning does not
    /// uncover sensitive media; it has its own reveal, as on Mastodon.
    func showsMedia(of post: some Revealable) -> Bool {
        !post.isSensitive || shownMedia.contains(post.revealKey)
    }

    func toggleContent(of post: some Revealable) {
        openedWarnings.formSymmetricDifference([post.revealKey])
    }

    func toggleMedia(of post: some Revealable) {
        shownMedia.formSymmetricDifference([post.revealKey])
    }
}
