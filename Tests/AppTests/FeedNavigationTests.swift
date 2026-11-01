@testable import CrossPost
import SwiftUI
import XCTest

final class FeedNavigationTests: XCTestCase {
    private let ids = ["a", "b", "c", "d", "e", "f", "g", "h"]

    func testMoveStepsByIDAndClampsAtTheEnds() {
        XCTAssertEqual(FeedNavigation.move(from: "c", by: 1, in: ids, visible: []), "d")
        XCTAssertEqual(FeedNavigation.move(from: "c", by: -1, in: ids, visible: []), "b")
        XCTAssertEqual(FeedNavigation.move(from: "h", by: 1, in: ids, visible: []), "h")
        XCTAssertEqual(FeedNavigation.move(from: "a", by: -1, in: ids, visible: []), "a")
    }

    func testFocusStaysOnTheSamePostWhenARefreshInsertsPostsAbove() {
        let refreshed = ["new1", "new2"] + ids
        XCTAssertEqual(FeedNavigation.move(from: "c", by: 1, in: refreshed, visible: []), "d")
        XCTAssertEqual(FeedNavigation.move(from: "c", by: -1, in: refreshed, visible: []), "b")
    }

    func testWithoutAUsableSelectionFocusStartsOnTheFirstVisiblePost() {
        let visible: Set = ["e", "f"]
        XCTAssertEqual(FeedNavigation.move(from: nil, by: 1, in: ids, visible: visible), "e")
        XCTAssertEqual(FeedNavigation.move(from: "deleted", by: -1, in: ids, visible: visible), "e")
        XCTAssertEqual(FeedNavigation.move(from: nil, by: 1, in: ids, visible: []), "a")
        XCTAssertNil(FeedNavigation.move(from: nil, by: 1, in: [], visible: []))
    }

    func testPageMovesByWhatIsOnScreen() {
        let visible: Set = ["c", "d", "e"]
        XCTAssertEqual(FeedNavigation.page(forward: true, from: "d", in: ids, visible: visible), "f")
        XCTAssertEqual(FeedNavigation.page(forward: false, from: "d", in: ids, visible: visible), "a")
        XCTAssertEqual(FeedNavigation.page(forward: true, from: "g", in: ids, visible: ["g", "h"]), "h")
    }

    func testPageAlwaysMovesAtLeastOnePost() {
        // A post taller than the column leaves nothing wholly visible but itself.
        XCTAssertEqual(FeedNavigation.page(forward: true, from: "a", in: ids, visible: ["a"]), "b")
        // Focus scrolled away below the visible rows still moves down from itself.
        XCTAssertEqual(FeedNavigation.page(forward: true, from: "g", in: ids, visible: ["b", "c"]), "h")
    }

    func testPageFallsBackToAFixedStepWithoutVisibleRows() {
        let step = FeedNavigation.fallbackPage
        XCTAssertEqual(FeedNavigation.page(forward: true, from: "a", in: ids, visible: []), ids[step])
        XCTAssertEqual(FeedNavigation.page(forward: false, from: "h", in: ids, visible: []),
                       ids[ids.count - 1 - step])
    }

    @MainActor
    func testAFocusRequestIsClaimedOnceByItsColumnAndGoesStale() {
        let focus = FeedKeyboardFocus()
        focus.request(.bluesky)
        XCTAssertFalse(focus.claim(.mastodon))
        XCTAssertTrue(focus.claim(.bluesky))
        XCTAssertFalse(focus.claim(.bluesky), "a request is claimed once")

        focus.request(.mastodon)
        let later = Date.now.addingTimeInterval(FeedKeyboardFocus.requestLifetime + 0.1)
        XCTAssertFalse(focus.claim(.mastodon, now: later), "an unclaimed request goes stale")
    }

    func testKeyMapping() {
        let cases: [KeyCase] = [
            KeyCase(.downArrow, "", expected: .next),
            KeyCase(.upArrow, "", expected: .previous),
            KeyCase(.leftArrow, "", expected: .focus(.mastodon)),
            KeyCase(.rightArrow, "", expected: .focus(.bluesky)),
            KeyCase("j", "j", expected: .next),
            KeyCase("k", "k", expected: .previous),
            KeyCase("J", "J", [.capsLock], expected: .next),
            KeyCase(.space, " ", expected: .pageDown),
            KeyCase(.space, " ", [.shift], expected: .pageUp),
            KeyCase("r", "r", expected: .reply),
            KeyCase("l", "l", expected: .like),
            KeyCase("b", "b", expected: .repost),
            KeyCase(.return, "\r", expected: .open),
            KeyCase(.escape, "\u{1B}", expected: .back)
        ]
        for keyCase in cases {
            XCTAssertEqual(keyCase.command, keyCase.expected, keyCase.description)
        }
    }

    func testModifiedKeysAndDeleteAreNeverBound() {
        let unbound: [KeyCase] = [
            KeyCase("j", "j", [.command]),
            KeyCase("k", "k", [.option]),
            KeyCase("l", "l", [.command]),
            KeyCase("R", "R", [.shift]),
            KeyCase("J", "J", [.shift]),
            KeyCase(.downArrow, "", [.control]),
            KeyCase(.leftArrow, "", [.shift]),
            KeyCase(.space, " ", [.command]),
            KeyCase(.delete, "\u{7F}"),
            KeyCase(.deleteForward, ""),
            KeyCase("x", "x")
        ]
        for keyCase in unbound {
            XCTAssertNil(keyCase.command, keyCase.description)
        }
    }
}

private struct KeyCase {
    let key: KeyEquivalent
    let characters: String
    let modifiers: EventModifiers
    var expected: FeedKeyCommand?

    init(_ key: KeyEquivalent, _ characters: String, _ modifiers: EventModifiers = [],
         expected: FeedKeyCommand? = nil) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
        self.expected = expected
    }

    var command: FeedKeyCommand? {
        FeedKeyCommand(key: key, characters: characters, modifiers: modifiers)
    }

    var description: String {
        "\(characters.debugDescription) \(modifiers)"
    }
}
