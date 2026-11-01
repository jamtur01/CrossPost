import Observation

/// Which content warnings and sensitive media the user has opened this session.
/// Owned by the panel so it outlives recycled timeline rows and pushed routes, and
/// keyed by the underlying post so a boost row and its thread share the choice.
/// Never persisted: every launch starts with warnings closed and media covered.
@MainActor
@Observable
final class PostReveals {
    private var openedWarnings: Set<NativeRef> = []
    private var shownMedia: Set<NativeRef> = []

    /// Whether the post's body, media, link card, and quote are visible: always
    /// for posts without a content warning, otherwise once the user opens it.
    func showsContent(of post: FeedPost) -> Bool {
        post.contentWarning == nil || openedWarnings.contains(post.nativeRef)
    }

    /// Whether the post's media is unblurred. Opening a content warning does not
    /// uncover sensitive media; it has its own reveal, as on Mastodon.
    func showsMedia(of post: FeedPost) -> Bool {
        !post.isSensitive || shownMedia.contains(post.nativeRef)
    }

    func toggleContent(of post: FeedPost) {
        openedWarnings.formSymmetricDifference([post.nativeRef])
    }

    func toggleMedia(of post: FeedPost) {
        shownMedia.formSymmetricDifference([post.nativeRef])
    }
}

extension FeedPost {
    /// The Mastodon content warning shown in place of the post, if it has one.
    var contentWarning: String? {
        guard let spoilerText, !spoilerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return spoilerText
    }
}
