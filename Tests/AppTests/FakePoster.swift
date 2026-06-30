import Foundation
@testable import CrossPost

enum FakePostError: Error { case boom }

/// A `Poster` that records the threads (and resume refs) it's asked to post and
/// returns canned results — a single `result`, or a per-call `resultQueue` so one
/// test can model a first-attempt partial followed by a successful retry.
final class FakePoster: Poster, @unchecked Sendable {
    let target: PostTarget
    var result: Result<[PostedItem], Error> = .success([PostedItem(url: "https://example/1")])
    var resultQueue: [Result<[PostedItem], Error>] = []
    private(set) var postedThreads: [[DraftPost]] = []
    private(set) var continuedFrom: [NativeRef?] = []

    init(target: PostTarget) { self.target = target }

    func post(thread: [DraftPost], continuingFrom ref: NativeRef?) async throws -> [PostedItem] {
        postedThreads.append(thread)
        continuedFrom.append(ref)
        if !resultQueue.isEmpty { return try resultQueue.removeFirst().get() }
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
