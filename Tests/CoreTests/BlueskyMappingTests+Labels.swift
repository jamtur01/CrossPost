import ATProtoKit
@testable import CrossPost
import XCTest

/// Bluesky labels mapped onto the content warning and sensitive-media fields.
extension BlueskyMappingTests {
    private static let moderator = "did:plc:ar7c4by46qjdydhdevvrndac" // Bluesky's moderation service

    private struct LabelCase {
        let name: String
        var labels: [[String: Any]] = []
        var selfLabels: [String] = []
        var warning: String?
        var sensitive = false
    }

    private func label(_ value: String, from source: String = moderator, negated: Bool = false,
                       at time: String = "2024-06-01T12:00:00.000Z") -> [String: Any] {
        ["src": source, "uri": "at://did:plc:alice/app.bsky.feed.post/aaa111", "val": value,
         "neg": negated, "cts": time]
    }

    /// The `bluesky_post` fixture with these labels, and these self-labels in its record.
    private func labelled(_ labels: [[String: Any]], selfLabels: [String]) throws -> FeedPost {
        let fixture = try JSONSerialization.jsonObject(with: fixtureData("bluesky_post")) as? [String: Any]
        var post = try XCTUnwrap(fixture?["post"] as? [String: Any])
        post["labels"] = labels
        if !selfLabels.isEmpty {
            var record = try XCTUnwrap(post["record"] as? [String: Any])
            record["labels"] = ["$type": "com.atproto.label.defs#selfLabels",
                                "values": selfLabels.map { ["val": $0] }]
            post["record"] = record
        }
        let view = try Self.decoder.decode(AppBskyLexicon.Feed.PostViewDefinition.self,
                                           from: JSONSerialization.data(withJSONObject: post))
        return BlueskyFeedService.feedPost(fromPostView: view)
    }

    func testLabelsBecomeAWarningOrSensitiveMediaWithBlueskysDefaults() throws {
        let later = "2024-06-02T00:00:00.000Z"
        let cases = [
            LabelCase(name: "unlabelled"),
            LabelCase(name: "media label", labels: [label("sexual")], sensitive: true),
            LabelCase(name: "legacy gore", labels: [label("gore")], sensitive: true),
            LabelCase(name: "warn", labels: [label("!warn")], warning: "Content warning"),
            LabelCase(name: "hide outranks warn", labels: [label("!warn"), label("!hide"), label("porn")],
                      warning: "Hidden by moderators", sensitive: true),
            LabelCase(name: "author's self-label", selfLabels: ["graphic-media"], sensitive: true),
            LabelCase(name: "author can't warn their own post", labels: [label("!warn", from: "did:plc:alice")],
                      selfLabels: ["!warn"]),
            LabelCase(name: "negated", labels: [label("porn", negated: true, at: later), label("porn")]),
            LabelCase(name: "negated by another labeler",
                      labels: [label("porn"), label("porn", from: "did:plc:other", negated: true, at: later)],
                      sensitive: true),
            LabelCase(name: "not understood, or shown by default",
                      labels: [label("spam"), label("!no-unauthenticated"), label("nudity")])
        ]
        for testCase in cases {
            let post = try labelled(testCase.labels, selfLabels: testCase.selfLabels)
            XCTAssertEqual(post.spoilerText, testCase.warning, testCase.name)
            XCTAssertEqual(post.isSensitive, testCase.sensitive, testCase.name)
        }
    }

    func testLabelledQuoteIsCovered() throws {
        let fixture = try JSONSerialization.jsonObject(with: fixtureData("bluesky_quote")) as? [String: Any]
        var item = try XCTUnwrap(fixture)
        var post = try XCTUnwrap(item["post"] as? [String: Any])
        var embed = try XCTUnwrap(post["embed"] as? [String: Any])
        var record = try XCTUnwrap(embed["record"] as? [String: Any])
        record["labels"] = [label("!warn"), label("sexual")]
        embed["record"] = record
        post["embed"] = embed
        item["post"] = post
        let feedItem = try Self.decoder.decode(AppBskyLexicon.Feed.FeedViewPostDefinition.self,
                                               from: JSONSerialization.data(withJSONObject: item))
        let quoting = try XCTUnwrap(BlueskyFeedService.feedPost(from: feedItem))
        let quoted = try XCTUnwrap(quoting.quoted)

        XCTAssertEqual(quoted.spoilerText, "Content warning")
        XCTAssertTrue(quoted.isSensitive)
        XCTAssertNil(quoting.spoilerText, "the quote's labels don't cover the post quoting it")
        XCTAssertFalse(quoting.isSensitive)
    }
}
