import XCTest
import ATProtoKit
@testable import CrossPost

/// Fixture-decoded tests for the Bluesky SDK -> `FeedPost` mapping — the most
/// complex mapping in the app. The `app.bsky` view types are `Codable`, so the
/// fixtures are decoded straight with a `JSONDecoder` (dates are handled inside
/// ATProtoKit's own `decodeDate`, so no date strategy is needed). Post *records*
/// live behind ATProtoKit's `UnknownType`, which only decodes into a real
/// `PostRecord` when the type is present in the process-global record registry,
/// so it is registered once before the suite runs.
final class BlueskyMappingTests: XCTestCase {
    private static let decoder = JSONDecoder()

    override func setUp() async throws {
        try await super.setUp()
        // Populate the registry so `record.getRecord(ofType: PostRecord.self)`
        // resolves text/facets/reply instead of silently falling back to a
        // dictionary. Idempotent: `register` skips types already present.
        await ATRecordTypeRegistry.shared.register(types: [AppBskyLexicon.Feed.PostRecord.self])
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    private func feedItem(_ name: String) throws -> AppBskyLexicon.Feed.FeedViewPostDefinition {
        try Self.decoder.decode(AppBskyLexicon.Feed.FeedViewPostDefinition.self, from: fixtureData(name))
    }

    private func mapped(_ name: String) throws -> FeedPost {
        try XCTUnwrap(BlueskyFeedService.feedPost(from: feedItem(name)), "feedPost(from:) returned nil")
    }

    /// The (text, url) pairs of every linked run in an attributed string.
    private func links(_ s: AttributedString) -> [(text: String, url: URL)] {
        s.runs.compactMap { run in
            guard let url = run.link else { return nil }
            return (String(s[run.range].characters), url)
        }
    }

    // MARK: - Plain post

    func testPlainPostMapsIdentityTextRefAndWebURL() throws {
        let post = try mapped("bluesky_post")

        // id is namespaced by the at:// uri; there is no boost key on a plain post.
        XCTAssertEqual(post.id, "bluesky:at://did:plc:alice/app.bsky.feed.post/aaa111")
        XCTAssertEqual(post.authorHandle, "@alice.bsky.social")
        XCTAssertEqual(post.authorName, "Alice")
        XCTAssertEqual(post.authorID, "did:plc:alice")
        XCTAssertEqual(String(post.text.characters), "hello @alice.bsky.social")
        XCTAssertFalse(post.isReply)
        XCTAssertNil(post.boostedBy)

        // A top-level post is its own thread root (uri+cid repeated).
        guard case .bluesky(let uri, let cid, let rootURI, let rootCID) = post.nativeRef else {
            return XCTFail("expected a bluesky native ref")
        }
        XCTAssertEqual(uri, "at://did:plc:alice/app.bsky.feed.post/aaa111")
        XCTAssertEqual(cid, "bafypost1")
        XCTAssertEqual(rootURI, uri)
        XCTAssertEqual(rootCID, cid)

        XCTAssertEqual(post.webURL, URL(string: "https://bsky.app/profile/alice.bsky.social/post/aaa111"))
    }

    func testPlainPostResolvesMentionFacetToProfileLink() throws {
        let post = try mapped("bluesky_post")
        // The mention facet (bytes [6,24)) must become a link to the DID profile.
        XCTAssertEqual(links(post.text).map(\.text), ["@alice.bsky.social"])
        XCTAssertEqual(links(post.text).first?.url,
                       URL(string: "https://bsky.app/profile/did:plc:alice"))
    }

    func testPlainPostCarriesEngagementCounts() throws {
        let post = try mapped("bluesky_post")
        XCTAssertEqual(post.replyCount, 3)
        XCTAssertEqual(post.repostCount, 5)
        XCTAssertEqual(post.likeCount, 9)
    }

    func testViewerLikeAndRepostDriveStateAndRecordURIs() throws {
        let post = try mapped("bluesky_post")
        // A viewer with like/repost uris means the user acted; the record uris are
        // kept so the action can be undone.
        XCTAssertTrue(post.isLiked)
        XCTAssertTrue(post.isReposted)
        XCTAssertEqual(post.likeRecordURI, "at://did:plc:me/app.bsky.feed.like/like123")
        XCTAssertEqual(post.repostRecordURI, "at://did:plc:me/app.bsky.feed.repost/repost123")
    }

    func testImageEmbedPopulatesFullSizeURLAndAltText() throws {
        let post = try mapped("bluesky_post")
        XCTAssertEqual(post.images.count, 1)
        XCTAssertEqual(post.images[0].url, URL(string: "https://cdn.bsky.app/img/full/aaa.jpg"))
        XCTAssertEqual(post.images[0].altText, "a sunset over the sea")
        XCTAssertEqual(post.images[0].kind, .image)
        XCTAssertNil(post.card)
        XCTAssertNil(post.quoted)
    }

    // MARK: - Repost (reasonRepost)

    func testRepostKeysIdByReposterAndAttributesBooster() throws {
        let post = try mapped("bluesky_repost")
        // Keyed by the reposter's DID so the same post reposted by different
        // people (or also present as an original) stays a distinct feed row.
        XCTAssertEqual(post.id, "bluesky:did:plc:bob:at://did:plc:alice/app.bsky.feed.post/aaa111")
        XCTAssertEqual(post.boostedBy, "Bob Booster")
        // Content is still the original author's.
        XCTAssertEqual(post.authorHandle, "@alice.bsky.social")
        XCTAssertEqual(String(post.text.characters), "hello world")
        // No viewer on the fixture => not acted on.
        XCTAssertFalse(post.isLiked)
        XCTAssertFalse(post.isReposted)
        XCTAssertNil(post.likeRecordURI)
    }

    func testSamePostRepostedByDifferentPeopleStaysDistinct() throws {
        // The core reason reposts are keyed by reposter: identical post view,
        // different boosters must produce different ids (and differ from the
        // un-boosted original) so ForEach ids don't collide.
        let postView = try feedItem("bluesky_repost").post
        let byBob = BlueskyFeedService.feedPost(fromPostView: postView,
                                                boostedBy: "Bob", boostKey: "did:plc:bob")
        let byEve = BlueskyFeedService.feedPost(fromPostView: postView,
                                                boostedBy: "Eve", boostKey: "did:plc:eve")
        let original = BlueskyFeedService.feedPost(fromPostView: postView)

        XCTAssertNotEqual(byBob.id, byEve.id)
        XCTAssertNotEqual(byBob.id, original.id)
        XCTAssertNotEqual(byEve.id, original.id)
        XCTAssertEqual(byBob.id, "bluesky:did:plc:bob:at://did:plc:alice/app.bsky.feed.post/aaa111")
        XCTAssertEqual(original.id, "bluesky:at://did:plc:alice/app.bsky.feed.post/aaa111")
    }

    // MARK: - Reply

    func testReplyIsFlaggedAndThreadRootComesFromReplyReference() throws {
        let post = try mapped("bluesky_reply")
        XCTAssertTrue(post.isReply)
        // The reply's own uri differs from the thread root; the root (uri+cid)
        // must propagate into the native ref so a continuation threads correctly.
        guard case .bluesky(let uri, _, let rootURI, let rootCID) = post.nativeRef else {
            return XCTFail("expected a bluesky native ref")
        }
        XCTAssertEqual(uri, "at://did:plc:alice/app.bsky.feed.post/reply999")
        XCTAssertEqual(rootURI, "at://did:plc:carol/app.bsky.feed.post/root001")
        XCTAssertEqual(rootCID, "bafyroot")
    }

    func testBarePostViewDerivesThreadRootFromRecordReply() throws {
        // When no explicit replyRoot is supplied (e.g. a reply parent hydrated on
        // its own), the root is derived from the post record's own reply field.
        let postView = try feedItem("bluesky_reply").post
        let post = BlueskyFeedService.feedPost(fromPostView: postView)

        XCTAssertTrue(post.isReply)   // record.reply != nil
        guard case .bluesky(_, _, let rootURI, let rootCID) = post.nativeRef else {
            return XCTFail("expected a bluesky native ref")
        }
        XCTAssertEqual(rootURI, "at://did:plc:carol/app.bsky.feed.post/root001")
        XCTAssertEqual(rootCID, "bafyroot")
    }

    // MARK: - Quote / record embeds

    func testQuotePostMapsNestedAuthorTextImageAndWebURL() throws {
        let post = try mapped("bluesky_quote")
        let quoted = try XCTUnwrap(post.quoted, "expected a quoted post")

        XCTAssertEqual(quoted.id, "bluesky:at://did:plc:dave/app.bsky.feed.post/orig555")
        XCTAssertEqual(quoted.authorHandle, "@dave.bsky.social")
        XCTAssertEqual(quoted.authorName, "Dave")
        XCTAssertEqual(String(quoted.text.characters), "the quoted words")
        XCTAssertEqual(quoted.imageURL, URL(string: "https://cdn.bsky.app/img/full/qqq.jpg"))
        XCTAssertEqual(quoted.webURL, URL(string: "https://bsky.app/profile/dave.bsky.social/post/orig555"))
        // A record-only embed carries no media on the outer post.
        XCTAssertTrue(post.images.isEmpty)
    }

    func testRecordWithMediaMapsBothQuotedAndMedia() throws {
        let post = try mapped("bluesky_record_with_media")
        let quoted = try XCTUnwrap(post.quoted, "expected a quoted post")

        XCTAssertEqual(quoted.authorHandle, "@dave.bsky.social")
        XCTAssertEqual(String(quoted.text.characters), "quoted alongside media")
        // ...and the outer media is populated too.
        XCTAssertEqual(post.images.count, 1)
        XCTAssertEqual(post.images[0].url, URL(string: "https://cdn.bsky.app/img/full/rwm.jpg"))
        XCTAssertEqual(post.images[0].altText, "media beside a quote")
    }

    // MARK: - External embeds (gif vs link card)

    func testExternalGifEmbedBecomesPlayableGifMedia() throws {
        let post = try mapped("bluesky_external_gif")
        // A direct .gif link (even with a query string) plays inline as gif media,
        // not a link card.
        XCTAssertNil(post.card)
        XCTAssertEqual(post.images.count, 1)
        XCTAssertEqual(post.images[0].kind, .gif)
        XCTAssertEqual(post.images[0].altText, "celebrate")   // gif alt text is the title
        XCTAssertEqual(post.images[0].url, URL(string: "https://media.tenor.com/celebrate.gif?hh=200"))
    }

    func testExternalNonGifEmbedBecomesLinkCard() throws {
        let post = try mapped("bluesky_external_link")
        XCTAssertTrue(post.images.isEmpty)
        let card = try XCTUnwrap(post.card, "expected a link card")
        XCTAssertEqual(card.title, "A Big Story")
        XCTAssertEqual(card.description, "everything about the story")
        XCTAssertEqual(card.imageURL, URL(string: "https://www.nytimes.com/thumb.jpg"))
        XCTAssertEqual(card.providerName, "www.nytimes.com")   // provider is the URL host
    }

    // MARK: - gifMedia boundary (only direct .gif URLs are playable)

    func testGifMediaTreatsOnlyDirectGifURLsAsPlayable() {
        // name, uri, expected-to-be-gif
        let cases: [(name: String, uri: String, isGif: Bool)] = [
            ("plain gif", "https://x.test/a.gif", true),
            ("gif with query", "https://x.test/a.gif?width=100", true),
            ("uppercase extension", "https://x.test/a.GIF", true),
            ("png", "https://x.test/a.png", false),
            ("mp4", "https://x.test/a.mp4", false),
            ("html page", "https://x.test/story.html", false),
            (".gif in path but not suffix", "https://x.test/a.gif/more", false),
        ]
        for c in cases {
            let external = AppBskyLexicon.Embed.ExternalDefinition.ViewExternal(
                uri: c.uri, title: "t", description: "d", thumbnailImageURL: nil)
            let media = BlueskyFeedService.gifMedia(from: external)
            if c.isGif {
                XCTAssertEqual(media?.kind, .gif, "\(c.name) should be a gif")
                XCTAssertEqual(media?.url, URL(string: c.uri), "\(c.name) keeps the full uri")
            } else {
                XCTAssertNil(media, "\(c.name) must not be treated as a gif")
            }
        }
    }

    // MARK: - videoMedia / aspect ratio

    func testVideoMediaUsesPlaylistURLAltTextAndAspectRatio() throws {
        let view = AppBskyLexicon.Embed.VideoDefinition.View(
            cid: "vidcid",
            playlistURI: "https://video.bsky.app/playlist.m3u8",
            thumbnailImageURL: "https://video.bsky.app/thumb.jpg",
            altText: "a clip",
            aspectRatio: .init(width: 1600, height: 900))
        let media = try XCTUnwrap(BlueskyFeedService.videoMedia(from: view))

        XCTAssertEqual(media.kind, .video)
        XCTAssertEqual(media.url, URL(string: "https://video.bsky.app/playlist.m3u8"))
        XCTAssertEqual(media.altText, "a clip")
        XCTAssertEqual(media.aspectRatio, 1600.0 / 900.0)
    }

    func testAspectRatioIsNilWhenHeightIsZero() {
        // Division-by-zero guard: a zero height yields no ratio rather than inf/NaN.
        XCTAssertNil(BlueskyFeedService.aspect(.init(width: 100, height: 0)))
        XCTAssertEqual(BlueskyFeedService.aspect(.init(width: 100, height: 50)), 2.0)
        XCTAssertNil(BlueskyFeedService.aspect(nil))
    }

    // MARK: - Notification mapping (referencedURI + notification(from:hydrated:))

    private func notification(_ name: String) throws -> AppBskyLexicon.Notification.Notification {
        try Self.decoder.decode(AppBskyLexicon.Notification.Notification.self, from: fixtureData(name))
    }

    /// Decode a minimal notification with a chosen reason and (optional) subject —
    /// lets the routing/kind tables cover every reason without a fixture apiece.
    private func inlineNotification(reason: String, reasonSubject: String?) throws
        -> AppBskyLexicon.Notification.Notification {
        let subjectField = reasonSubject.map { "\"reasonSubject\": \"\($0)\"," } ?? ""
        let json = """
        {
          "uri": "at://did:plc:actor/app.bsky.feed.post/self123",
          "cid": "bafyinline",
          "author": { "did": "did:plc:actor", "handle": "actor.bsky.social" },
          "reason": "\(reason)",
          \(subjectField)
          "record": { "$type": "app.bsky.feed.like", "createdAt": "2024-06-01T00:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2024-06-01T00:00:00.000Z"
        }
        """
        return try Self.decoder.decode(AppBskyLexicon.Notification.Notification.self, from: Data(json.utf8))
    }

    /// The hydrated-post dict keyed exactly as the mapper keys it — by post uri — so
    /// a notification's referencedURI can select it. Built from the shared post fixture.
    private func hydratedPosts() throws -> [String: AppBskyLexicon.Feed.PostViewDefinition] {
        let post = try feedItem("bluesky_post").post
        return [post.uri: post]
    }

    func testReferencedURIRoutesByReason() throws {
        // reasonSubject is present for EVERY case, so nil results prove the reason
        // gates routing (not mere presence) and mention/reply/quote use uri, not it.
        let subject = "at://did:plc:alice/app.bsky.feed.post/aaa111"
        let selfURI = "at://did:plc:actor/app.bsky.feed.post/self123"
        let cases: [(reason: String, expected: String?)] = [
            ("mention", selfURI),
            ("reply", selfURI),
            ("quote", selfURI),
            ("like", subject),
            ("repost", subject),
            ("like-via-repost", subject),
            ("repost-via-repost", subject),
            ("follow", nil),
            ("starterpack-joined", nil),
            ("subscribed-post", nil),
            ("totally-new-reason", nil),
        ]
        for c in cases {
            let n = try inlineNotification(reason: c.reason, reasonSubject: subject)
            XCTAssertEqual(BlueskyFeedService.referencedURI(n), c.expected,
                           "\(c.reason) must route to \(c.expected ?? "nil")")
        }
    }

    func testKindMapsReasonFoldingViaRepostVariants() throws {
        // The -via-repost variants fold into their base kind; unknowns -> .other.
        let cases: [(reason: String, kind: FeedNotification.Kind)] = [
            ("mention", .mention),
            ("reply", .reply),
            ("quote", .quote),
            ("like", .like),
            ("like-via-repost", .like),
            ("repost", .repost),
            ("repost-via-repost", .repost),
            ("follow", .follow),
            ("starterpack-joined", .other),
            ("subscribed-post", .other),
            ("totally-new-reason", .other),
        ]
        for c in cases {
            let n = try inlineNotification(reason: c.reason, reasonSubject: nil)
            let mapped = BlueskyFeedService.notification(from: n, hydrated: [:])
            XCTAssertEqual(mapped.kind, c.kind, "\(c.reason) must map to \(c.kind)")
        }
    }

    func testLikeAttachesHydratedSubjectPostViaReferencedURI() throws {
        // The point of the refactor: the SAME referencedURI that decides what to
        // hydrate also selects which hydrated post to attach. The like's subject is
        // the post fixture's uri, so its mapped post (text included) rides along.
        let n = try notification("bluesky_notification_like")
        let mapped = BlueskyFeedService.notification(from: n, hydrated: try hydratedPosts())
        let post = try XCTUnwrap(mapped.post, "hydrated subject must attach")
        XCTAssertEqual(String(post.text.characters), "hello @alice.bsky.social")
    }

    func testFollowHasNoReferencedPostEvenWhenPostsExist() throws {
        // referencedURI is nil for a follow, so nothing attaches (no crash) even
        // though the hydrated dict is non-empty.
        let n = try notification("bluesky_notification_follow")
        let mapped = BlueskyFeedService.notification(from: n, hydrated: try hydratedPosts())
        XCTAssertNil(mapped.post)
    }

    func testLikeWithMissingHydratedSubjectHasNilPost() throws {
        // Graceful miss: the subject wasn't hydrated (e.g. deleted), so post is nil.
        let n = try notification("bluesky_notification_like")
        let mapped = BlueskyFeedService.notification(from: n, hydrated: [:])
        XCTAssertNil(mapped.post)
    }

    func testNotificationCarriesActorIdentityIdAndDate() throws {
        let n = try notification("bluesky_notification_like")
        let mapped = BlueskyFeedService.notification(from: n, hydrated: [:])
        XCTAssertEqual(mapped.id, "at://did:plc:bob/app.bsky.feed.like/like999")
        XCTAssertEqual(mapped.actorHandle, "@bob.bsky.social")
        XCTAssertEqual(mapped.actorName, "Bob Liker")
        XCTAssertEqual(mapped.actorID, "did:plc:bob")
        XCTAssertEqual(mapped.avatarURL, URL(string: "https://cdn.bsky.app/img/avatar/bob.jpg"))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(mapped.date, iso.date(from: "2024-06-02T09:30:00.000Z"))
    }

    func testActorNameFallsBackToHandleWhenDisplayNameBlank() throws {
        // displayName is "" on the follow fixture; displayOrHandle uses the handle.
        let n = try notification("bluesky_notification_follow")
        let mapped = BlueskyFeedService.notification(from: n, hydrated: [:])
        XCTAssertEqual(mapped.actorName, "carol.bsky.social")
        XCTAssertEqual(mapped.actorHandle, "@carol.bsky.social")
    }

    func testLikeViaRepostFoldsToLikeAndAttachesSubject() throws {
        // Fixture parity for the folded variant: kind collapses to .like and the
        // subject still routes through referencedURI to attach the hydrated post.
        let n = try notification("bluesky_notification_like_via_repost")
        let mapped = BlueskyFeedService.notification(from: n, hydrated: try hydratedPosts())
        XCTAssertEqual(mapped.kind, .like)
        XCTAssertEqual(String(try XCTUnwrap(mapped.post).text.characters), "hello @alice.bsky.social")
    }
}
