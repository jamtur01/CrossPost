@testable import CrossPost
import XCTest

final class MentionMergerTests: XCTestCase {
    private func mastodon(_ acct: String, name: String = "M", profile: String = "") -> MentionCandidate {
        MentionCandidate(target: .mastodon, handle: acct, displayName: name, avatarURL: nil, profileText: profile)
    }

    private func bluesky(_ handle: String, name: String = "B") -> MentionCandidate {
        MentionCandidate(target: .bluesky, handle: handle, displayName: name, avatarURL: nil, profileText: "")
    }

    func testMergesOnProfileLinkOrHandle() {
        let link = MentionMerger.merge(
            mastodon: [mastodon("pup@hachyderm.io", profile: #"<a href="https://bsky.app/profile/Pup.bsky.social">"#)],
            bluesky: [bluesky("pup.bsky.social")], pairs: []
        )
        XCTAssertEqual(link.map(\.blueskyHandle), ["pup.bsky.social"])
        let handle = MentionMerger.merge(
            mastodon: [mastodon("pup@hachyderm.io", profile: "also @pup.bsky.social.")],
            bluesky: [bluesky("pup.bsky.social")], pairs: []
        )
        XCTAssertEqual(handle.count, 1)
    }

    func testLinkToLongerDomainDoesNotMerge() {
        let people = MentionMerger.merge(
            mastodon: [mastodon("alice@x.y", profile: "https://bsky.app/profile/alice.example.com.au")],
            bluesky: [bluesky("alice.example.com")], pairs: []
        )
        XCTAssertEqual(people.count, 2)
    }

    func testHandleMustNotContinue() {
        let people = MentionMerger.merge(
            mastodon: [mastodon("pup@hachyderm.io", profile: "@pup.bsky.socialite")],
            bluesky: [bluesky("pup.bsky.social")], pairs: []
        )
        XCTAssertEqual(people.count, 2)
    }

    func testMergesBridgyFedAccounts() {
        let bridgedBluesky = MentionMerger.merge(
            mastodon: [mastodon("alice.bsky.social@bsky.brid.gy")],
            bluesky: [bluesky("alice.bsky.social")], pairs: []
        )
        XCTAssertEqual(bridgedBluesky.count, 1)
        let bridgedMastodon = MentionMerger.merge(
            mastodon: [mastodon("bob@mastodon.social")],
            bluesky: [bluesky("bob.mastodon.social.ap.brid.gy")], pairs: []
        )
        XCTAssertEqual(bridgedMastodon.count, 1)
    }

    func testMergesSavedPairCaseInsensitively() {
        let pairs = [MentionPair(mastodonAcct: "Pup@Hachyderm.io", blueskyHandle: "lk.example.com")]
        let people = MentionMerger.merge(mastodon: [mastodon("pup@hachyderm.io")],
                                         bluesky: [bluesky("LK.example.com")], pairs: pairs)
        XCTAssertEqual(people.count, 1)
    }

    func testSameNameAloneDoesNotMerge() {
        let people = MentionMerger.merge(mastodon: [mastodon("a@x.y", name: "Sam")],
                                         bluesky: [bluesky("sam.bsky.social", name: "Sam")], pairs: [])
        XCTAssertEqual(people.count, 2)
    }

    func testEachCandidateMergesOnce() {
        let profile = "@pup.bsky.social"
        let people = MentionMerger.merge(
            mastodon: [mastodon("one@x.y", profile: profile), mastodon("two@x.y", profile: profile)],
            bluesky: [bluesky("pup.bsky.social")], pairs: []
        )
        XCTAssertEqual(people.map(\.mastodonAcct), ["one@x.y", "two@x.y"])
        XCTAssertEqual(people.map(\.blueskyHandle), ["pup.bsky.social", nil])
    }

    func testSavedPairBeatsAutomaticMatch() {
        let pairs = [MentionPair(mastodonAcct: "alice@x.y", blueskyHandle: "alice-new.bsky.social")]
        let people = MentionMerger.merge(
            mastodon: [mastodon("alice@x.y", profile: "@alice-old.bsky.social")],
            bluesky: [bluesky("alice-old.bsky.social"), bluesky("alice-new.bsky.social")], pairs: pairs
        )
        XCTAssertEqual(people.map(\.mastodonAcct), ["alice@x.y", nil])
        XCTAssertEqual(people.map(\.blueskyHandle), ["alice-new.bsky.social", "alice-old.bsky.social"])
    }

    func testAccountPairedElsewhereIsNotMatchedAutomatically() {
        let pairs = [MentionPair(mastodonAcct: "bob@x.y", blueskyHandle: "bob.bsky.social")]
        let people = MentionMerger.merge(
            mastodon: [mastodon("impostor@x.y", profile: "@bob.bsky.social")],
            bluesky: [bluesky("bob.bsky.social")], pairs: pairs
        )
        XCTAssertEqual(people.map(\.mastodonAcct), ["impostor@x.y", "bob@x.y"])
        XCTAssertEqual(people.map(\.blueskyHandle), [nil, "bob.bsky.social"])
    }

    func testSavedPairCompletesSingleNetworkRow() {
        let pairs = [MentionPair(mastodonAcct: "pup@hachyderm.io", blueskyHandle: "lk.example.com")]
        let people = MentionMerger.merge(mastodon: [mastodon("pup@hachyderm.io")], bluesky: [], pairs: pairs)
        XCTAssertEqual(people.first?.blueskyHandle, "lk.example.com")
        let reverse = MentionMerger.merge(mastodon: [], bluesky: [bluesky("lk.example.com")], pairs: pairs)
        XCTAssertEqual(reverse.first?.mastodonAcct, "pup@hachyderm.io")
    }

    func testRowsAlternateNetworks() {
        let people = MentionMerger.merge(mastodon: [mastodon("m1@x.y"), mastodon("m2@x.y")],
                                         bluesky: [bluesky("b1.bsky.social")], pairs: [])
        XCTAssertEqual(people.map { $0.mastodonAcct ?? $0.blueskyHandle },
                       ["m1@x.y", "b1.bsky.social", "m2@x.y"])
    }
}
