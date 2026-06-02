import XCTest
@testable import CrossPost

private struct StubPoster: Poster {
    let target: PostTarget
    let behavior: Behavior
    enum Behavior {
        case ok([PostedItem])
        case partial(ThreadPostError)
        case fail(Error)
    }
    func post(thread: [DraftPost]) async throws -> [PostedItem] {
        switch behavior {
        case .ok(let items): return items
        case .partial(let e): throw e
        case .fail(let e): throw e
        }
    }
}

private struct Boom: Error, CustomStringConvertible { let description = "boom" }

final class CrossPostCoordinatorTests: XCTestCase {
    private let limits = TargetLimits(mastodonMax: 500)
    private let coordinator = CrossPostCoordinator()

    func testBlockedWhenValidationFails() async {
        let thread = [DraftPost(text: String(repeating: "a", count: 400))] // > bluesky 300
        let outcome = await coordinator.publish(thread: thread, to: [.bluesky], using: [], limits: limits)
        guard case .blocked(let issues) = outcome else { return XCTFail("expected blocked") }
        XCTAssertEqual(issues, [.tooLong(postIndex: 0, target: .bluesky, count: 400, limit: 300)])
    }

    func testSuccessForBothTargets() async {
        let thread = [DraftPost(text: "hi")]
        let posters: [Poster] = [
            StubPoster(target: .mastodon, behavior: .ok([PostedItem(url: "m1")])),
            StubPoster(target: .bluesky, behavior: .ok([PostedItem(url: "b1")])),
        ]
        let outcome = await coordinator.publish(thread: thread, to: [.mastodon, .bluesky], using: posters, limits: limits)
        guard case .completed(let results) = outcome else { return XCTFail("expected completed") }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.target), [.mastodon, .bluesky])
        for r in results {
            guard case .success(let posted) = r.outcome else { return XCTFail("expected success") }
            XCTAssertEqual(posted.count, 1)
        }
    }

    func testPartialFailureIsReportedPerTarget() async {
        let thread = [DraftPost(text: "hi")]
        let posters: [Poster] = [
            StubPoster(target: .mastodon, behavior: .ok([PostedItem(url: "m1")])),
            StubPoster(target: .bluesky, behavior: .fail(Boom())),
        ]
        let outcome = await coordinator.publish(thread: thread, to: [.mastodon, .bluesky], using: posters, limits: limits)
        guard case .completed(let results) = outcome else { return XCTFail("expected completed") }
        guard case .success = results[0].outcome else { return XCTFail("mastodon should succeed") }
        guard case .failure(let msg) = results[1].outcome else { return XCTFail("bluesky should fail") }
        XCTAssertTrue(msg.contains("boom"))
    }

    func testMidThreadFailureReportedAsPartial() async {
        let thread = [DraftPost(text: "a"), DraftPost(text: "b")]
        let err = ThreadPostError(posted: [PostedItem(url: "m1")], failedIndex: 1, underlying: Boom())
        let posters: [Poster] = [StubPoster(target: .mastodon, behavior: .partial(err))]
        let outcome = await coordinator.publish(thread: thread, to: [.mastodon], using: posters, limits: limits)
        guard case .completed(let results) = outcome,
              case .partial(let posted, let failedIndex, let msg) = results[0].outcome
        else { return XCTFail("expected partial") }
        XCTAssertEqual(posted.map(\.url), ["m1"])
        XCTAssertEqual(failedIndex, 1)
        XCTAssertTrue(msg.contains("boom"))
    }

    func testMissingPosterForTargetIsFailure() async {
        let thread = [DraftPost(text: "hi")]
        let outcome = await coordinator.publish(thread: thread, to: [.bluesky], using: [], limits: limits)
        guard case .completed(let results) = outcome,
              case .failure(let msg) = results[0].outcome
        else { return XCTFail("expected failure") }
        XCTAssertTrue(msg.contains("Bluesky"))
    }
}
