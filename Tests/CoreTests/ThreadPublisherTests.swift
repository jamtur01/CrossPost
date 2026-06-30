import XCTest
@testable import CrossPost

/// Records the (root, parent) refs passed for each post and hands back an incrementing Int ref.
private actor FakePublisher: ThreadPublisher {
    typealias Ref = Int
    struct Call: Equatable { let root: Int?; let parent: Int? }
    private(set) var calls: [Call] = []
    private var next = 0
    let failAt: Int?

    init(failAt: Int? = nil) { self.failAt = failAt }

    func publishOne(_ draft: DraftPost, root: Int?, parent: Int?) async throws -> (ref: Int, item: PostedItem) {
        calls.append(Call(root: root, parent: parent))
        if calls.count - 1 == failAt {
            struct Boom: Error {}
            throw Boom()
        }
        next += 1
        return (ref: next, item: PostedItem(url: "url-\(next)"))
    }

    func recordedCalls() -> [Call] { calls }

    // Map a Mastodon statusID ("5") to Int refs so resume can be exercised here.
    nonisolated func resumeRefs(from ref: NativeRef) -> (root: Int, parent: Int)? {
        guard case .mastodon(let statusID) = ref, let value = Int(statusID) else { return nil }
        return (root: value, parent: value)
    }
}

final class ThreadPublisherTests: XCTestCase {
    func testFirstPostHasNoRootOrParent() async throws {
        let pub = FakePublisher()
        _ = try await runThread([DraftPost(text: "a")], using: pub)
        let calls = await pub.recordedCalls()
        XCTAssertEqual(calls, [.init(root: nil, parent: nil)])
    }

    func testThreePostThreadLinksRootAndParent() async throws {
        let pub = FakePublisher()
        let drafts = [DraftPost(text: "a"), DraftPost(text: "b"), DraftPost(text: "c")]
        let posted = try await runThread(drafts, using: pub)

        XCTAssertEqual(posted.map(\.url), ["url-1", "url-2", "url-3"])
        let calls = await pub.recordedCalls()
        // post 1: no refs; post 2: root=1,parent=1; post 3: root=1,parent=2
        XCTAssertEqual(calls, [
            .init(root: nil, parent: nil),
            .init(root: 1, parent: 1),
            .init(root: 1, parent: 2),
        ])
    }

    func testMidThreadFailureThrowsWithPostedSoFar() async {
        let pub = FakePublisher(failAt: 1) // second post fails
        let drafts = [DraftPost(text: "a"), DraftPost(text: "b"), DraftPost(text: "c")]
        do {
            _ = try await runThread(drafts, using: pub)
            XCTFail("expected throw")
        } catch let e as ThreadPostError {
            XCTAssertEqual(e.failedIndex, 1)
            XCTAssertEqual(e.posted.map(\.url), ["url-1"])
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testContinuingFromSeedsRootAndParentFromLandedPost() async throws {
        let pub = FakePublisher()
        // Resume from a landed post whose ref maps to Int 5: the first new post must
        // reply to it (root=5, parent=5), the next chains onto the freshly posted ref.
        let drafts = [DraftPost(text: "b"), DraftPost(text: "c")]
        let posted = try await runThread(drafts, using: pub, continuingFrom: .mastodon(statusID: "5"))

        XCTAssertEqual(posted.map(\.url), ["url-1", "url-2"])
        let calls = await pub.recordedCalls()
        XCTAssertEqual(calls, [
            .init(root: 5, parent: 5),   // first new post replies to the landed post
            .init(root: 5, parent: 1),   // next keeps the landed root, parents on the new post
        ])
    }
}
