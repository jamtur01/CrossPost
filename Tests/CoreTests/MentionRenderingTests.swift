@testable import CrossPost
import XCTest

final class MentionRenderingTests: XCTestCase {
    private let both = MentionPerson(mastodonAcct: "puppetfather@hachyderm.io",
                                     blueskyHandle: "puppetfather.bsky.social",
                                     displayName: "Luke Kanies")

    private func draft(_ text: String, _ person: MentionPerson, at location: Int) -> DraftPost {
        let length = person.visibleText.utf16.count
        return DraftPost(text: text, mentions: [MentionSpan(location: location, length: length, person: person)])
    }

    func testVisibleTextPrefersMastodonUsername() {
        XCTAssertEqual(both.visibleText, "@puppetfather")
        let bluesky = MentionPerson(blueskyHandle: "alice.bsky.social", displayName: "Alice")
        XCTAssertEqual(bluesky.visibleText, "@alice")
        let custom = MentionPerson(blueskyHandle: "jamesturnbull.net", displayName: "James")
        XCTAssertEqual(custom.visibleText, "@jamesturnbull.net")
    }

    func testRendersEachNetworksHandle() {
        let post = draft("Hi @puppetfather!", both, at: 3)
        XCTAssertEqual(post.rendered(for: .mastodon).text, "Hi @puppetfather@hachyderm.io!")
        XCTAssertEqual(post.rendered(for: .bluesky).text, "Hi @puppetfather.bsky.social!")
        XCTAssertEqual(post.rendered(for: .bluesky).mentions, [])
    }

    func testMissingNetworkGetsDisplayNameThenOtherHandle() {
        let mastodonOnly = MentionPerson(mastodonAcct: "bob@example.social", displayName: "Bob")
        XCTAssertEqual(draft("@bob", mastodonOnly, at: 0).rendered(for: .bluesky).text, "Bob")
        let nameless = MentionPerson(mastodonAcct: "bob@example.social", displayName: "  ")
        XCTAssertEqual(draft("@bob", nameless, at: 0).rendered(for: .bluesky).text, "bob@example.social")
        let blueskyOnly = MentionPerson(blueskyHandle: "alice.bsky.social", displayName: "")
        XCTAssertEqual(draft("@alice", blueskyOnly, at: 0).rendered(for: .mastodon).text, "alice.bsky.social")
    }

    func testMultipleMentionsAfterEmojiUseUTF16Offsets() {
        let alice = MentionPerson(blueskyHandle: "alice.bsky.social", displayName: "Alice")
        let text = "👨‍👩‍👧‍👦 @puppetfather and @alice"
        let utf16Text = text as NSString
        let first = utf16Text.range(of: "@puppetfather")
        let second = utf16Text.range(of: "@alice")
        let post = DraftPost(text: text, mentions: [
            MentionSpan(location: first.location, length: first.length, person: both),
            MentionSpan(location: second.location, length: second.length, person: alice)
        ])
        XCTAssertEqual(post.rendered(for: .mastodon).text,
                       "👨‍👩‍👧‍👦 @puppetfather@hachyderm.io and Alice")
        XCTAssertEqual(post.rendered(for: .bluesky).text,
                       "👨‍👩‍👧‍👦 @puppetfather.bsky.social and @alice.bsky.social")
    }

    func testOutOfRangeSpanIsLeftAsTyped() {
        let post = DraftPost(text: "@pup", mentions: [MentionSpan(location: 2, length: 20, person: both)])
        XCTAssertEqual(post.rendered(for: .mastodon).text, "@pup")
    }

    func testSavedDraftWithoutMentionsDecodes() throws {
        let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"hi","#
            + #""attachments":[],"visibility":"public"}"#
        let post = try JSONDecoder().decode(DraftPost.self, from: Data(legacy.utf8))
        XCTAssertEqual(post.text, "hi")
        XCTAssertEqual(post.mentions, [])
    }
}
