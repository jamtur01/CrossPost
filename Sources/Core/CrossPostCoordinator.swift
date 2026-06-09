import Foundation

struct CrossPostCoordinator: Sendable {
    init() {}

    func publish(thread: [DraftPost],
                        to targets: [PostTarget],
                        using posters: [Poster],
                        limits: TargetLimits) async -> CrossPostOutcome {
        let issues = PostValidator.validate(thread: thread, targets: targets, limits: limits)
        guard issues.isEmpty else { return .blocked(issues: issues) }

        // The networks are independent, so post to them concurrently; results
        // keep the caller's target order.
        let results = await withTaskGroup(of: (Int, PostResult).self) { group in
            for (index, target) in targets.enumerated() {
                let poster = posters.first(where: { $0.target == target })
                group.addTask { (index, await Self.publish(thread: thread, to: target, using: poster)) }
            }
            var indexed: [(Int, PostResult)] = []
            for await entry in group { indexed.append(entry) }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return .completed(results: results)
    }

    private static func publish(thread: [DraftPost], to target: PostTarget,
                                using poster: Poster?) async -> PostResult {
        guard let poster else {
            return PostResult(target: target,
                              outcome: .failure(message: "No account configured for \(target.displayName)"))
        }
        do {
            let posted = try await poster.post(thread: thread)
            return PostResult(target: target, outcome: .success(posted: posted))
        } catch let e as ThreadPostError {
            return PostResult(target: target,
                              outcome: .partial(posted: e.posted,
                                                failedIndex: e.failedIndex,
                                                message: e.underlying.userMessage))
        } catch {
            return PostResult(target: target, outcome: .failure(message: error.userMessage))
        }
    }
}
