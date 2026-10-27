@testable import CrossPost
import XCTest

@MainActor
final class MentionCompletionTests: XCTestCase {
    private func directory(_ services: [PostTarget: FakeFeedService]) -> MentionDirectory {
        MentionDirectory(pairStore: MentionPairStore(url: URL.temporaryDirectory
                .appending(path: "pairs-\(UUID()).json"))) { target in
            guard let service = services[target] else { throw FakeFeedService.FakeError.boom }
            return service
        }
    }

    private func candidate(_ target: PostTarget, _ handle: String) -> MentionCandidate {
        MentionCandidate(target: target, handle: handle, displayName: handle, avatarURL: nil, profileText: "")
    }

    func testSearchesSelectedNetworksAndMerges() async {
        let mastodon = FakeFeedService()
        mastodon.mentionCandidatesToReturn = [candidate(.mastodon, "pup@x.y")]
        let bluesky = FakeFeedService()
        bluesky.mentionCandidatesToReturn = [candidate(.bluesky, "pup.bsky.social")]
        let results = await directory([.mastodon: mastodon, .bluesky: bluesky])
            .search("pup", on: [.mastodon, .bluesky])
        XCTAssertEqual(results.people.count, 2)
        XCTAssertEqual(results.failed, [])
        XCTAssertEqual(mastodon.mentionQueries, ["pup"])
    }

    func testOneNetworkFailingKeepsTheOther() async {
        let bluesky = FakeFeedService()
        bluesky.mentionCandidatesToReturn = [candidate(.bluesky, "pup.bsky.social")]
        let results = await directory([.bluesky: bluesky]).search("pup", on: [.mastodon, .bluesky])
        XCTAssertEqual(results.people.map(\.blueskyHandle), ["pup.bsky.social"])
        XCTAssertEqual(results.failed, [.mastodon])
    }

    func testCompletionDebouncesAndKeepsOnlyLatestQuery() async {
        var queries: [String] = []
        let completion = MentionCompletion(debounce: .milliseconds(20)) { query in
            queries.append(query)
            return MentionDirectory.Results(people: [MentionPerson(blueskyHandle: "\(query).bsky.social",
                                                                   displayName: query)], failed: [])
        }
        completion.update(text: "@pu", caret: 3)
        completion.update(text: "@pup", caret: 4)
        await waitUntil { !completion.people.isEmpty }
        XCTAssertEqual(queries, ["pup"])
        XCTAssertEqual(completion.people.map(\.displayName), ["pup"])
        XCTAssertTrue(completion.isActive)

        // A new query must not offer the old query's people while its search runs.
        completion.update(text: "@bob", caret: 4)
        XCTAssertEqual(completion.people, [])
        XCTAssertNil(completion.selected)
        XCTAssertFalse(completion.isActive)
    }

    func testFailureWithNoResultsShowsMessage() async {
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: [], failed: [.mastodon, .bluesky])
        }
        completion.update(text: "@pup", caret: 4)
        await waitUntil { completion.failureMessage != nil }
        XCTAssertEqual(completion.failureMessage, "Couldn't search Mastodon or Bluesky.")
    }

    func testLeavingTheTokenDismisses() async {
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: [MentionPerson(displayName: "x")], failed: [])
        }
        completion.update(text: "@pup", caret: 4)
        await waitUntil { completion.isActive }
        completion.update(text: "@pup ", caret: 5)
        XCTAssertFalse(completion.isActive)
        XCTAssertEqual(completion.people, [])
    }

    func testSelectionWraps() async {
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: [MentionPerson(displayName: "a"), MentionPerson(displayName: "b")],
                                     failed: [])
        }
        completion.update(text: "@ab", caret: 3)
        await waitUntil { completion.people.count == 2 }
        completion.moveSelection(by: -1)
        XCTAssertEqual(completion.selected?.displayName, "b")
        completion.moveSelection(by: 1)
        XCTAssertEqual(completion.selected?.displayName, "a")
    }

    /// Waits for the search to land rather than sleeping a fixed time, which a
    /// slow CI runner can outlast.
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return XCTFail("condition not met within 2s", file: file, line: line)
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
