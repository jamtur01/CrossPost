import Foundation
@testable import CrossPost

enum FakePostError: Error { case boom }

/// A `Poster` that records the threads it's asked to post and returns a canned
/// result (success, full failure, or a mid-thread `ThreadPostError`).
final class FakePoster: Poster, @unchecked Sendable {
    let target: PostTarget
    var result: Result<[PostedItem], Error> = .success([PostedItem(url: "https://example/1")])
    private(set) var postedThreads: [[DraftPost]] = []

    init(target: PostTarget) { self.target = target }

    func post(thread: [DraftPost]) async throws -> [PostedItem] {
        postedThreads.append(thread)
        return try result.get()
    }
}

/// Records which targets were asked for and vends pre-configured fake posters.
final class PosterRecorder: @unchecked Sendable {
    var postersByTarget: [PostTarget: FakePoster] = [:]
    private(set) var requestedTargets: [[PostTarget]] = []

    func make(_ targets: [PostTarget], _ store: AccountStore) -> [Poster] {
        requestedTargets.append(targets)
        return targets.map { postersByTarget[$0] ?? FakePoster(target: $0) }
    }
}
