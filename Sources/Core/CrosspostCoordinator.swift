import Foundation

public struct CrosspostCoordinator: Sendable {
    public init() {}

    public func publish(thread: [DraftPost],
                        to targets: [PostTarget],
                        using posters: [Poster],
                        limits: TargetLimits) async -> CrosspostOutcome {
        let issues = PostValidator.validate(thread: thread, targets: targets, limits: limits)
        guard issues.isEmpty else { return .blocked(issues: issues) }

        var results: [PostResult] = []
        for target in targets {
            guard let poster = posters.first(where: { $0.target == target }) else {
                results.append(PostResult(target: target,
                                          outcome: .failure(message: "No account configured for \(target.displayName)")))
                continue
            }
            do {
                let posted = try await poster.post(thread: thread)
                results.append(PostResult(target: target, outcome: .success(posted: posted)))
            } catch let e as ThreadPostError {
                results.append(PostResult(target: target,
                                          outcome: .partial(posted: e.posted,
                                                            failedIndex: e.failedIndex,
                                                            message: String(describing: e.underlying))))
            } catch {
                results.append(PostResult(target: target, outcome: .failure(message: String(describing: error))))
            }
        }
        return .completed(results: results)
    }
}
