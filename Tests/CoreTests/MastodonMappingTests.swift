@testable import CrossPost
import TootSDK
import XCTest

/// Fixture-decoded tests for the Mastodon feed mapping. The fixtures are decoded
/// with a `JSONDecoder` configured like TootSDK's internal `TootDecoder`
/// (snake_case keys + its multi-format date strategy), since that initializer
/// isn't accessible from here.
final class MastodonMappingTests: XCTestCase {
    func testStreamEventsOnlyInvalidateRelevantContent() throws {
        let post = try decodePost("mastodon_reply")
        XCTAssertEqual(MastodonFeedService.feedUpdate(from: .connectionUp), .connected)
        XCTAssertEqual(MastodonFeedService.feedUpdate(from: .connectionDown), .disconnected)
        XCTAssertEqual(MastodonFeedService.feedUpdate(from: .receivedEvent(.update(post))), .home)
        XCTAssertEqual(MastodonFeedService.feedUpdate(from: .receivedEvent(.delete("post"))), .postChanged)
        let convo = TootSDK.Conversation(id: "c", accounts: [post.account], unread: true, lastPost: post)
        XCTAssertEqual(MastodonFeedService.feedUpdate(from: .receivedEvent(.conversation(convo))), .messages)
        XCTAssertNil(MastodonFeedService.feedUpdate(from: .receivedEvent(.announcementDelete("announcement"))))
    }

    func testMentionCandidateKeepsBioAndFieldsForMerging() throws {
        let post = try decodePost("mastodon_reply") { json in
            var account = json["account"] as? [String: Any] ?? [:]
            account["note"] = "<p>Puppets</p>"
            account["fields"] = [["name": "Bluesky",
                                  "value": #"<a href="https://bsky.app/profile/pup.bsky.social">pup</a>"#]]
            json["account"] = account
        }
        let candidate = MastodonFeedService.mentionCandidate(from: post.account, localDomain: "a.example")
        XCTAssertEqual(candidate.target, .mastodon)
        XCTAssertTrue(candidate.profileText.contains("<p>Puppets</p>"))
        XCTAssertTrue(candidate.profileText.contains("bsky.app/profile/pup.bsky.social"))
    }

    func testLocalMentionCandidateIsQualifiedWithItsServer() throws {
        let local = try decodePost("mastodon_reply") { json in
            var account = json["account"] as? [String: Any] ?? [:]
            account["acct"] = "alice"
            account["url"] = "https://web.a.example/@alice"
            json["account"] = account
        }.account
        XCTAssertEqual(MastodonFeedService.mentionCandidate(from: local, localDomain: "a.example").handle,
                       "alice@a.example")
        XCTAssertEqual(MastodonFeedService.mentionCandidate(from: local, localDomain: "b.example").handle,
                       "alice@b.example")
        // Without the instance's domain, fall back to the profile URL's host.
        XCTAssertEqual(MastodonFeedService.mentionCandidate(from: local, localDomain: nil).handle,
                       "alice@web.a.example")
        let remote = try decodePost("mastodon_reply") { json in
            var account = json["account"] as? [String: Any] ?? [:]
            account["acct"] = "bob@elsewhere.example"
            json["account"] = account
        }.account
        XCTAssertEqual(MastodonFeedService.mentionCandidate(from: remote, localDomain: "a.example").handle,
                       "bob@elsewhere.example")
    }

    func testDirectMessageMappingDropsAddressingMentions() throws {
        let message = try decodePost("mastodon_reply") { json in
            json["content"] = #"<p><span class="h-card"><a href="https://a.example/@bob">@<span>bob</span></a></span> "#
                + #"<span class="h-card"><a href="https://b.example/@cy">@<span>cy@b.example</span></a></span> "#
                + "see you at 5, @dee knows</p>"
            json["visibility"] = "direct"
        }
        XCTAssertEqual(MastodonFeedService.messageText(from: message), "see you at 5, @dee knows")
        XCTAssertTrue(MastodonFeedService.directMessage(from: message, ownID: message.account.id).isFromMe)
        XCTAssertFalse(MastodonFeedService.directMessage(from: message, ownID: "someone-else").isFromMe)

        let mentionOnly = try decodePost("mastodon_reply") { json in
            json["content"] = "<p>@bob</p>"
        }
        XCTAssertEqual(MastodonFeedService.messageText(from: mentionOnly), "@bob")

        let other = try decodePost("mastodon_reply") { json in
            var account = json["account"] as? [String: Any] ?? [:]
            account["id"] = "2"
            account["acct"] = "cy@b.example"
            account["display_name"] = ""
            json["account"] = account
        }.account
        let group = TootSDK.Conversation(id: "c1", accounts: [message.account, other], unread: true, lastPost: message)
        let convo = try XCTUnwrap(MastodonFeedService.conversation(from: group))
        XCTAssertEqual(
            convo.otherName,
            "\(displayOrHandle(message.account.displayName, message.account.acct)), cy@b.example"
        )
        XCTAssertEqual(convo.otherID, message.account.id)
        XCTAssertEqual(convo.lastMessage, "see you at 5, @dee knows")
        XCTAssertEqual(convo.unreadCount, 1)
        XCTAssertNil(MastodonFeedService.conversation(from: .init(
            id: "c2",
            accounts: [],
            unread: false,
            lastPost: nil
        )))
    }

    func testDirectMessageCannotSilentlyAddRecipients() throws {
        func extra(_ text: String) throws -> [String] {
            try MastodonFeedService.extraRecipients(in: text, participants: ["alice", "cy@b.example"],
                                                    localDomain: "Home.example")
        }
        XCTAssertEqual(try extra("I'm concerned about @bob@example.com and @dee, again @bob@example.com"),
                       ["bob@example.com", "dee"])
        XCTAssertEqual(try extra("@Alice@home.example @alice @CY@b.example hi"), [])
        XCTAssertEqual(try extra("mail me@x.example or see https://x.example/@bob"), [])
        // Expected values come from Mastodon's own Account::MENTION_RE in Ruby.
        XCTAssertEqual(try extra("note\u{200C}@bob a\u{200D}@dee \u{F870}@eve"), ["bob", "dee", "eve"])
        XCTAssertEqual(try extra("x@bob é@bob \u{2160}@bob =@bob /@bob"), [])
        XCTAssertEqual(try extra("@cy@b.example\u{0F0B}x and @cy@b.example."), ["cy@b.example\u{0F0B}x"])
        XCTAssertEqual(try extra("@Bob.Smith.@x"), ["Bob.Smith", "x"])
    }

    func testConversationKeepsOnlyItsOwnAudience() throws {
        func post(_ id: String, from author: String, mentioning mentioned: [String],
                  visibility: String = "direct", at time: String) throws -> Post {
            try decodePost("mastodon_reply") { json in
                json["id"] = id
                json["visibility"] = visibility
                json["created_at"] = "2026-10-26T10:00:\(time).000Z"
                var account = json["account"] as? [String: Any] ?? [:]
                account["id"] = author
                json["account"] = account
                json["mentions"] = mentioned.map { [
                    "id": $0,
                    "username": $0,
                    "acct": $0,
                    "url": "https://a.example/@\($0)"
                ] }
            }
        }
        let posts = try [
            post("later", from: "me", mentioning: ["alice"], at: "30"),
            post("first", from: "alice", mentioning: ["me"], at: "10"),
            post("addsBob", from: "alice", mentioning: ["me", "bob"], at: "20"),
            post("public", from: "alice", mentioning: ["me"], visibility: "public", at: "25")
        ]
        let kept = MastodonFeedService.conversationPosts(posts, participantIDs: ["alice"], ownID: "me")
        XCTAssertEqual(kept.map(\.id), ["first", "later"])

        let notes = try [
            post("note", from: "me", mentioning: [], at: "40"),
            post("noteToSelf", from: "me", mentioning: ["me"], at: "50")
        ]
        let selfKept = MastodonFeedService.conversationPosts(posts + notes, participantIDs: ["me"], ownID: "me")
        XCTAssertEqual(selfKept.map(\.id), ["note", "noteToSelf"])
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = withFraction.date(from: string) ?? plain.date(from: string) {
                return date
            }
            if let seconds = TimeInterval(string) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw try DecodingError.dataCorruptedError(
                in: decoder.singleValueContainer(), debugDescription: "bad date: \(string)"
            )
        }
        return decoder
    }()

    private func decodePost(_ name: String) throws -> Post {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json")
        return try Self.decoder.decode(Post.self, from: Data(contentsOf: url))
    }

    /// Decodes a fixture after `patch` edits its JSON — for fields TootSDK exposes
    /// as `let` (e.g. an account's emoji list).
    private func decodePost(_ name: String, patch: (inout [String: Any]) -> Void) throws -> Post {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        patch(&json)
        return try Self.decoder.decode(Post.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private static func emojiJSON(_ shortcode: String) -> [[String: Any]] {
        [[
            "shortcode": shortcode,
            "url": "https://e.io/\(shortcode).gif",
            "static_url": "https://e.io/\(shortcode).png",
            "visible_in_picker": true
        ]]
    }

    private func decodeQuote(_ name: String) throws -> Quote {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
            "missing fixture \(name).json"
        )
        let post = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let data = try JSONSerialization.data(
            withJSONObject: ["state": "accepted", "quoted_status": post]
        )
        return try Self.decoder.decode(Quote.self, from: data)
    }

    func testBoostUsesOuterIDWhileNativeRefAndContentComeFromTheBoostedStatus() throws {
        let mapped = try MastodonFeedService.feedPost(from: decodePost("mastodon_boost"))

        XCTAssertEqual(mapped.id, "mastodon:BOOST-1") // outer entry id stays distinct
        XCTAssertEqual(mapped.boostedBy, "Bob Booster") // attributed to the reposter
        XCTAssertEqual(mapped.authorHandle, "@alice@h.io") // content is the original author's
        XCTAssertEqual(String(mapped.text.characters), "original toot")
        XCTAssertEqual(mapped.likeCount, 8) // counts from the boosted status

        guard case let .mastodon(statusID) = mapped.nativeRef else { return XCTFail("expected mastodon ref") }
        XCTAssertEqual(statusID, "INNER-9") // like/reply target the real status
    }

    func testReplyInheritsVisibilitySpoilerAndSensitive() throws {
        let mapped = try MastodonFeedService.feedPost(from: decodePost("mastodon_reply"))

        XCTAssertEqual(mapped.visibility, "private")
        XCTAssertEqual(mapped.spoilerText, "content warning")
        XCTAssertTrue(mapped.isSensitive)
        XCTAssertTrue(mapped.isReply)
    }

    func testReplyNamesTheMentionedParentAuthor() throws {
        let post = try decodePost("mastodon_reply")
        post.inReplyToAccountId = "acc-bob"
        post.mentions = [
            Mention(id: "acc-carol", username: "carol", url: "https://c.io/@carol", acct: "carol@c.io"),
            Mention(id: "acc-bob", username: "bob", url: "https://b.io/@bob", acct: "bob@b.io")
        ]

        XCTAssertEqual(MastodonFeedService.feedPost(from: post).replyToHandle, "@bob@b.io")
    }

    func testSelfReplyNamesTheAuthor() throws {
        let post = try decodePost("mastodon_reply")
        post.inReplyToAccountId = post.account.id

        XCTAssertEqual(MastodonFeedService.feedPost(from: post).replyToHandle, "@alice@h.io")
    }

    func testReplyToUnmentionedAccountHasNoHandle() throws {
        let post = try decodePost("mastodon_reply")
        post.inReplyToAccountId = "acc-unknown"

        let mapped = MastodonFeedService.feedPost(from: post)
        XCTAssertNil(mapped.replyToHandle)
        XCTAssertTrue(mapped.isReply)
    }

    func testBoostCarriesBoosterAuthorAndContentEmojiAsStaticImages() throws {
        let post = try decodePost("mastodon_boost") { json in
            json["account"] = (json["account"] as? [String: Any] ?? [:])
                .merging(["emojis": Self.emojiJSON("booster")]) { $1 }
            var reblog = json["reblog"] as? [String: Any] ?? [:]
            reblog["account"] = (reblog["account"] as? [String: Any] ?? [:])
                .merging(["emojis": Self.emojiJSON("verified")]) { $1 }
            reblog["emojis"] = Self.emojiJSON("python")
            json["reblog"] = reblog
        }

        XCTAssertEqual(MastodonFeedService.feedPost(from: post).emojis.mapValues(\.absoluteString), [
            "booster": "https://e.io/booster.png",
            "verified": "https://e.io/verified.png",
            "python": "https://e.io/python.png"
        ])
    }

    func testProfileCarriesDisplayNameEmoji() throws {
        let post = try decodePost("mastodon_reply") { json in
            json["account"] = (json["account"] as? [String: Any] ?? [:])
                .merging(["emojis": Self.emojiJSON("verified")]) { $1 }
        }

        XCTAssertEqual(MastodonFeedService.profile(from: post.account).emojis.mapValues(\.absoluteString),
                       ["verified": "https://e.io/verified.png"])
    }

    func testMapsMediaKindsLinkCardCountsAndSensitive() throws {
        let mapped = try MastodonFeedService.feedPost(from: decodePost("mastodon_media_card"))

        XCTAssertEqual(mapped.images.count, 2)
        XCTAssertEqual(mapped.images[0].kind, .image)
        XCTAssertEqual(mapped.images[0].altText, "a cat")
        XCTAssertEqual(mapped.images[0].previewURL, URL(string: "https://h.io/cat-preview.png"))
        XCTAssertEqual(mapped.images[1].kind, .video) // Mastodon video/gifv → .video
        XCTAssertEqual(mapped.images[1].previewURL, URL(string: "https://h.io/clip-preview.jpg"))

        XCTAssertEqual(mapped.card?.title, "Headline")
        XCTAssertEqual(mapped.card?.providerName, "Example News")

        XCTAssertEqual(mapped.likeCount, 7) // favourites_count
        XCTAssertEqual(mapped.repostCount, 3)
        XCTAssertEqual(mapped.replyCount, 2)
        XCTAssertTrue(mapped.isSensitive)
    }

    func testQuotedPostUsesPreviewImageAndFallsBackToOriginal() throws {
        let quote = try decodeQuote("mastodon_media_card")
        let preview = try XCTUnwrap(MastodonFeedService.quotedPost(from: quote))

        XCTAssertEqual(preview.imageURL, URL(string: "https://h.io/cat-preview.png"))
        XCTAssertEqual(preview.webURL, URL(string: "https://h.io/@alice/MEDIA-1"))

        guard case let .post(post)? = quote.quotedPost else {
            return XCTFail("expected quoted post")
        }
        post.mediaAttachments[0].previewUrl = nil
        let fallback = try XCTUnwrap(MastodonFeedService.quotedPost(from: quote))

        XCTAssertEqual(fallback.imageURL, URL(string: "https://h.io/cat.png"))
        XCTAssertEqual(fallback.webURL, preview.webURL)
    }

    func testQuoteSupportRequiresMastodon44() {
        XCTAssertEqual(MastodonFeedService.supportsQuotePosts(version: "4.4.0"), true)
        XCTAssertEqual(MastodonFeedService.supportsQuotePosts(version: "4.5.1"), true)
        XCTAssertEqual(MastodonFeedService.supportsQuotePosts(version: "5.0.0-alpha.1"), true)
        XCTAssertEqual(MastodonFeedService.supportsQuotePosts(version: "4.4.0-nightly.2025-06-01"), true)
        XCTAssertEqual(MastodonFeedService.supportsQuotePosts(version: "4.3.8"), false)
        XCTAssertEqual(MastodonFeedService.supportsQuotePosts(version: "3.5.19"), false)
    }

    func testUnparseableVersionIsUndecided() {
        // Forks report free-form versions; the caller proceeds best-effort on nil.
        XCTAssertNil(MastodonFeedService.supportsQuotePosts(version: "compatible fork"))
        XCTAssertNil(MastodonFeedService.supportsQuotePosts(version: ""))
    }
}
